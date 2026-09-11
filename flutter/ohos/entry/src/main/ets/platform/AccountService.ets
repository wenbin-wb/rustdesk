import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ConfigManager, UserProfile } from './ConfigStorage';
import {
  getApiServer, setLocalOption, getLocalOption, LOCAL_OPTION_ACCESS_TOKEN,
  saveAddressBook, getUuid, AddressBook, AbEntry, AbPeer
} from './RustDeskBridge';

const DOMAIN = 0x0000;
const TAG = 'RustDeskAccount';

/**
 * The account: signing in, and the address book that comes with it.
 *
 * The core is not signed in by this. Signing in is HTTP against the API server, which is what the
 * desktop client does and the reason this lives in ArkTS at all -- ArkTS holds the login and knows
 * the server address. What the core is given is the *result*: the token, stored under the key the
 * core and the rest of the app read when they build an authenticated request, and the fetched
 * address book written into the core's store so aliases, tags and remembered passwords survive a
 * restart.
 *
 * That split is what was missing before. The old code signed in and kept the token to itself, so
 * the book was never fetched and the account's entries never appeared no matter who was signed in.
 *
 * Written as functions rather than a class of statics: ArkTS rejects `this` inside a static method,
 * and these have no state to hang on a class anyway.
 */

export interface LoginResult {
  success: boolean;
  message: string;
  user?: UserProfile;
  /** Set when the server wants a second factor, so the caller can ask for the code. */
  requires2fa?: boolean;
  /** Set when the server wants an email verification code. */
  requiresVerification?: boolean;
  /** The intermediate token a second-factor or verification step is presented with. */
  secret?: string;
}

export interface SyncResult {
  success: boolean;
  message: string;
  peers: number;
}

/**
 * A replied HTTP response before it is interpreted.
 *
 * The body is kept as text rather than parsed here because each endpoint has its own shape, and
 * ArkTS has no indexable type to hand a generic object around in -- so each caller parses into the
 * interface it expects.
 */
interface TextReply {
  ok: boolean;
  status: number;
  text: string;
}

interface AccountUser {
  name?: string;
  email?: string;
  avatar?: string;
}

/** The login reply, as the API server sends it. */
interface LoginResponseBody {
  access_token?: string;
  type?: string;
  tfa_type?: string;
  secret?: string;
  error?: string;
  user?: AccountUser;
}

/** Any reply carrying an error string. */
interface ErrorReply {
  error?: string;
}

/** `/api/ab/personal` */
interface PersonalBookReply {
  guid?: string;
  error?: string;
}

/** `/api/ab/shared/profiles`, one entry. */
interface SharedProfile {
  guid?: string;
  name?: string;
}

/** `/api/ab/peers`, one peer. */
interface ServerPeer {
  id?: string;
  username?: string;
  hostname?: string;
  alias?: string;
  platform?: string;
  tags?: string[];
}

/** `/api/ab/peers` */
interface PeersReply {
  peers?: ServerPeer[];
  error?: string;
}

/** `/api/ab/peers` request body. */
interface PeersRequest {
  guid: string;
}

/**
 * Sign in, then adopt the account's address book.
 *
 * The book is fetched before this returns, so a caller that navigates to a list on success sees the
 * account's entries rather than an empty list that fills in a moment later.
 */
export async function login(
  account: string,
  password: string,
  apiServerOverride?: string
): Promise<LoginResult> {
  if (!account.trim() || !password.trim()) {
    return { success: false, message: '账号或密码不能为空' };
  }

  const base = await resolveApiServer(apiServerOverride);
  if (!base) {
    return { success: false, message: '未配置 API 服务器' };
  }

  let id = '';
  let uuid = '';
  try {
    id = await ConfigManager.getInstance().getMyId();
    // The account server identifies a device by this, and it is what the desktop client sends.
    // Read from the core rather than generated here, so the server keeps one view of this device;
    // a generated value would look like a new device on every launch.
    uuid = getUuid();
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'device identity unavailable: %{public}s', JSON.stringify(e));
  }

  const payload = JSON.stringify({
    username: account.trim(),
    password: password.trim(),
    id: id,
    uuid: uuid,
    autoLogin: true,
    type: 'account'
  });

  const request = http.createHttp();
  try {
    const response = await request.request(`${base}/api/login`, {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      extraData: payload,
      connectTimeout: 10000,
      readTimeout: 10000
    });

    const text = typeof response.result === 'string'
      ? response.result
      : JSON.stringify(response.result);
    let parsed: LoginResponseBody;
    try {
      parsed = JSON.parse(text) as LoginResponseBody;
    } catch (e) {
      return { success: false, message: `服务器返回无法解析 (HTTP ${response.responseCode})` };
    }

    // A second factor and an email verification both arrive as a successful response carrying an
    // intermediate secret instead of a token. Reporting them as failures would be wrong -- the
    // password was accepted -- so they are surfaced for the caller to continue from.
    if (parsed.type === 'tfa' || parsed.tfa_type === 'tfa') {
      return { success: false, message: '需要两步验证码', requires2fa: true, secret: parsed.secret };
    }
    if (parsed.type === 'email' || parsed.type === 'verification') {
      return {
        success: false, message: '需要邮箱验证码',
        requiresVerification: true, secret: parsed.secret
      };
    }

    if (response.responseCode !== 200 || !parsed.access_token) {
      const reason = parsed.error
        ? String(parsed.error)
        : `服务器返回状态码 ${response.responseCode}`;
      return { success: false, message: reason };
    }

    const token = parsed.access_token;
    // Stored in the core's local options before anything is fetched: every later request reads the
    // token from there, so a fetch issued first would be unauthenticated.
    setLocalOption(LOCAL_OPTION_ACCESS_TOKEN, token);

    const profile: UserProfile = {
      username: parsed.user?.name ?? account.trim(),
      email: parsed.user?.email ?? '',
      token: token,
      avatar: parsed.user?.avatar ?? '',
      isLoggedIn: true
    };
    await ConfigManager.getInstance().saveUserProfile(profile);

    // Fetched now so the caller can show it immediately. A failure here is reported but does not
    // fail the login: the account is signed in either way, and the book can be re-fetched without
    // signing in again.
    const sync = await syncAddressBook();
    if (!sync.success) {
      hilog.warn(DOMAIN, TAG, 'signed in but the address book did not load: %{public}s',
        sync.message);
    }

    return { success: true, message: '登录成功', user: profile };
  } catch (e) {
    return {
      success: false,
      message: `无法连接到服务器 (${base}): ${e instanceof Error ? e.message : String(e)}`
    };
  } finally {
    request.destroy();
  }
}

/**
 * Sign out: clear the token from the core, then the stored profile.
 *
 * The token goes first. Leaving it would leave the core making authenticated requests for an
 * account the user has signed out of.
 */
export async function logout(): Promise<void> {
  try {
    setLocalOption(LOCAL_OPTION_ACCESS_TOKEN, '');
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'could not clear the token: %{public}s', JSON.stringify(e));
  }
  await ConfigManager.getInstance().clearUserProfile();
}

/** Whether a token is present, which is what the core treats as being signed in. */
export function isSignedIn(): boolean {
  try {
    return getLocalOption(LOCAL_OPTION_ACCESS_TOKEN).length > 0;
  } catch (e) {
    return false;
  }
}

/**
 * Fetch the account's address book and store it in the core.
 *
 * The server's shape is a personal book plus any books shared with the account. The personal one is
 * found through `/api/ab/personal`, which returns a guid. A server that predates it answers 404,
 * and that is not an error -- it means an older server whose book is addressed differently, so this
 * stops rather than reporting a failure.
 */
export async function syncAddressBook(): Promise<SyncResult> {
  const token = getLocalOption(LOCAL_OPTION_ACCESS_TOKEN);
  if (token.length === 0) {
    return { success: false, message: '未登录', peers: 0 };
  }
  const base = await resolveApiServer();
  if (!base) {
    return { success: false, message: '未配置 API 服务器', peers: 0 };
  }

  try {
    const personalReply = await post(`${base}/api/ab/personal`, token);
    if (personalReply.status === 404) {
      return { success: true, message: '服务器为旧版，跳过地址簿同步', peers: 0 };
    }
    if (!personalReply.ok) {
      return { success: false, message: errorOf(personalReply), peers: 0 };
    }

    const personal = JSON.parse(personalReply.text) as PersonalBookReply;
    const entries: AbEntry[] = [];
    const personalGuid = personal.guid ?? '';
    if (personalGuid.length > 0) {
      entries.push(await loadBook(base, token, personalGuid, 'personal'));
    }

    // Books shared with the account, each fetched by its own guid.
    const sharedReply = await post(`${base}/api/ab/shared/profiles`, token);
    if (sharedReply.ok) {
      const profiles = JSON.parse(sharedReply.text) as SharedProfile[];
      if (Array.isArray(profiles)) {
        for (const profile of profiles) {
          const guid = profile.guid ?? '';
          if (guid.length === 0) {
            continue;
          }
          const name = profile.name && profile.name.length > 0 ? profile.name : 'shared';
          entries.push(await loadBook(base, token, guid, name));
        }
      }
    }

    const book: AddressBook = { access_token: token, ab_entries: entries };
    saveAddressBook(book);

    let count = 0;
    for (const entry of entries) {
      count += entry.peers.length;
    }
    hilog.info(DOMAIN, TAG, 'address book synced: %{public}d books, %{public}d peers',
      entries.length, count);
    return { success: true, message: '地址簿已同步', peers: count };
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    hilog.warn(DOMAIN, TAG, 'address book sync failed: %{public}s', message);
    return { success: false, message: message, peers: 0 };
  }
}

/** One book's peers, in the core's entry shape. */
async function loadBook(base: string, token: string, guid: string, name: string): Promise<AbEntry> {
  const peers: AbPeer[] = [];
  const request: PeersRequest = { guid: guid };
  const reply = await post(`${base}/api/ab/peers`, token, request);
  if (reply.ok) {
    const parsed = JSON.parse(reply.text) as PeersReply;
    const list = parsed.peers ?? [];
    for (const raw of list) {
      const id = raw.id ?? '';
      if (id.length === 0) {
        continue;
      }
      peers.push({
        id: id,
        username: raw.username ?? '',
        hostname: raw.hostname ?? '',
        alias: raw.alias ?? '',
        platform: raw.platform ?? '',
        tags: raw.tags ?? []
      });
    }
  }
  return { guid: guid, name: name, tags: [], peers: peers };
}

/**
 * POST with the account token, leaving the body as text.
 *
 * Does not throw: an unreachable endpoint and a refused one are both ordinary here, and each
 * caller would otherwise repeat the same handling.
 */
async function post(url: string, token: string, payload?: Object): Promise<TextReply> {
  const request = http.createHttp();
  try {
    const response = await request.request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        // The scheme the desktop client uses; the server reads the token from here.
        'Authorization': `Bearer ${token}`
      },
      // Some endpoints take a POST with no parameters, which the server expects as an empty object
      // rather than an absent body.
      extraData: JSON.stringify(payload ?? {}),
      connectTimeout: 10000,
      readTimeout: 15000
    });
    const status = response.responseCode;
    return {
      ok: status === 200,
      status: status,
      text: typeof response.result === 'string'
        ? response.result
        : JSON.stringify(response.result)
    };
  } finally {
    request.destroy();
  }
}

/** An error message from a reply, falling back to the status when the body carries none. */
function errorOf(reply: TextReply): string {
  try {
    const parsed = JSON.parse(reply.text) as ErrorReply;
    if (parsed.error) {
      return String(parsed.error);
    }
  } catch (e) {
    // A non-JSON body on an error status is normal; the status is the useful part.
  }
  return `HTTP ${reply.status}`;
}

/**
 * The API server to talk to.
 *
 * Read from the core rather than from the front end's own copy: the core is what applies the
 * address, and signing in against a different server than the app is configured for would
 * authenticate in the wrong place.
 */
async function resolveApiServer(override?: string): Promise<string> {
  let server = override?.trim() ?? '';
  if (server.length === 0) {
    try {
      server = getApiServer().trim();
    } catch (e) {
      server = '';
    }
  }
  if (server.length === 0) {
    const config = await ConfigManager.getInstance().getServerConfig();
    server = config.apiServer.trim();
  }
  if (server.length === 0) {
    return '';
  }
  // A bare host:port is what the settings dialog accepts; the API is HTTP.
  if (!server.startsWith('http://') && !server.startsWith('https://')) {
    server = 'http://' + server;
  }
  // A trailing slash would double up against the paths appended to this.
  while (server.endsWith('/')) {
    server = server.substring(0, server.length - 1);
  }
  return server;
}
