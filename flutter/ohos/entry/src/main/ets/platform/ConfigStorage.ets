import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { getOption, setOptions } from './RustDeskBridge';

export interface ServerConfig {
  idServer: string;
  relayServer: string;
  apiServer: string;
  key: string;
  webClientUrl?: string;
}

export interface UserProfile {
  username: string;
  email: string;
  token: string;
  avatar: string;
  isLoggedIn: boolean;
}

export interface StoredPeer {
  id: string;
  username: string;
  hostname: string;
  alias: string;
  platform: string;
  lastConnectedTime: number;
  rememberedPassword?: string;
}

export class ConfigManager {
  private static instance: ConfigManager | null = null;
  private pref: preferences.Preferences | null = null;
  private isInitialized: boolean = false;
  /** Kept so preferences can be opened lazily; see ensureInit. */
  private context: common.Context | null = null;
  private initPromise: Promise<void> | null = null;

  private constructor() {}

  public static getInstance(): ConfigManager {
    if (!ConfigManager.instance) {
      ConfigManager.instance = new ConfigManager();
    }
    return ConfigManager.instance;
  }

  public async init(context: common.Context): Promise<void> {
    this.context = context;
    if (this.isInitialized && this.pref) {
      return;
    }
    try {
      this.pref = await preferences.getPreferences(context, 'rustdesk_settings');
      this.isInitialized = true;
    } catch {
      // Graceful fallback
    }
  }

  /**
   * Open preferences if they are not open yet, once.
   *
   * init() has to be called with a Context, and only the ability has one, so a reader that
   * runs before the ability got round to it would otherwise silently see nothing. Every
   * accessor awaits this first. The promise is cached so concurrent callers share one open
   * rather than racing.
   */
  private ensureInit(): Promise<void> {
    if (this.isInitialized && this.pref) {
      return Promise.resolve();
    }
    if (!this.context) {
      return Promise.resolve();
    }
    if (!this.initPromise) {
      this.initPromise = this.init(this.context);
    }
    return this.initPromise;
  }

  public async getServerConfig(): Promise<ServerConfig> {
    await this.ensureInit();
    // The core is authoritative for the server settings: it is what opens connections, and
    // its values are what the rest of the app reports. Preferences are only the UI's record.
    // Preferring the core here keeps the dialog showing the server actually in use rather
    // than a stale copy.
    const coreId = getOption('custom-rendezvous-server').trim();
    const coreRelay = getOption('relay-server').trim();
    const coreApi = getOption('api-server').trim();
    const coreKey = getOption('key').trim();

    if (!this.pref) {
      return {
        idServer: coreId,
        relayServer: coreRelay,
        apiServer: coreApi,
        key: coreKey,
        webClientUrl: ''
      };
    }
    const idServer = (await this.pref.get('custom_rendezvous_server', '')) as string;
    const relayServer = (await this.pref.get('relay_server', '')) as string;
    const apiServer = (await this.pref.get('api_server', '')) as string;
    const key = (await this.pref.get('key', '')) as string;
    const webClientUrl = (await this.pref.get('web_client_url', '')) as string;
    return {
      idServer: coreId.length > 0 ? coreId : idServer,
      relayServer: coreRelay.length > 0 ? coreRelay : relayServer,
      apiServer: coreApi.length > 0 ? coreApi : apiServer,
      key: coreKey.length > 0 ? coreKey : key,
      webClientUrl
    };
  }

  public async saveServerConfig(config: ServerConfig): Promise<void> {
    const id = config.idServer.trim();
    const relay = config.relayServer.trim();
    const api = config.apiServer.trim();
    const key = config.key.trim();
    const web = (config.webClientUrl || '').trim();

    // Push to the core first, and unconditionally. The core owns the settings that matter,
    // so a failure to open preferences must not also discard the user's server choice -- an
    // early return on a null pref is exactly what made saving appear to do nothing.
    // Keys are the core's own option names (libs/base/src/config/keys.rs); an empty value
    // clears the option, which is how the core returns to the public servers.
    setOptions({
      'custom-rendezvous-server': id,
      'relay-server': relay,
      'api-server': api,
      'key': key
    });

    await this.ensureInit();
    if (!this.pref) {
      return;
    }
    await this.pref.put('custom_rendezvous_server', id);
    await this.pref.put('relay_server', relay);
    await this.pref.put('api_server', api);
    await this.pref.put('key', key);
    await this.pref.put('web_client_url', web);
    await this.pref.flush();
  }

  public async getMyId(): Promise<string> {
    if (!this.pref) {
      return '';
    }
    return (await this.pref.get('my_id', '')) as string;
  }

  public async setMyId(id: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put('my_id', id);
    await this.pref.flush();
  }

  public async getOneTimePassword(): Promise<string> {
    if (!this.pref) {
      return '';
    }
    return (await this.pref.get('onetime_password', '')) as string;
  }

  public async setOneTimePassword(pwd: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put('onetime_password', pwd);
    await this.pref.flush();
  }

  public async getUserProfile(): Promise<UserProfile> {
    if (!this.pref) {
      return { username: '', email: '', token: '', avatar: '', isLoggedIn: false };
    }
    const username = (await this.pref.get('user_name', '')) as string;
    const email = (await this.pref.get('user_email', '')) as string;
    const token = (await this.pref.get('user_token', '')) as string;
    const avatar = (await this.pref.get('user_avatar', '')) as string;
    const isLoggedIn = token.length > 0;
    return { username, email, token, avatar, isLoggedIn };
  }

  public async saveUserProfile(profile: UserProfile): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put('user_name', profile.username);
    await this.pref.put('user_email', profile.email);
    await this.pref.put('user_token', profile.token);
    await this.pref.put('user_avatar', profile.avatar);
    await this.pref.flush();
  }

  public async clearUserProfile(): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.delete('user_name');
    await this.pref.delete('user_email');
    await this.pref.delete('user_token');
    await this.pref.delete('user_avatar');
    await this.pref.flush();
  }

  public async getRecentPeers(): Promise<StoredPeer[]> {
    if (!this.pref) {
      return [];
    }
    const jsonStr = (await this.pref.get('recent_peers', '[]')) as string;
    try {
      return JSON.parse(jsonStr) as StoredPeer[];
    } catch {
      return [];
    }
  }

  public async addRecentPeer(peer: StoredPeer): Promise<void> {
    if (!this.pref) {
      return;
    }
    const peers = await this.getRecentPeers();
    const filtered = peers.filter(p => p.id !== peer.id);
    filtered.unshift(peer);
    if (filtered.length > 30) {
      filtered.pop();
    }
    await this.pref.put('recent_peers', JSON.stringify(filtered));
    await this.pref.flush();
  }

  public async removeRecentPeer(id: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    const peers = await this.getRecentPeers();
    const filtered = peers.filter(p => p.id !== id);
    await this.pref.put('recent_peers', JSON.stringify(filtered));
    await this.pref.flush();
  }

  public async getPeerPassword(id: string): Promise<string> {
    if (!this.pref) {
      return '';
    }
    const cleanId = id.replace(/\s+/g, '');
    return (await this.pref.get('peer_pwd_' + cleanId, '')) as string;
  }

  public async savePeerPassword(id: string, pwd: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    const cleanId = id.replace(/\s+/g, '');
    if (pwd) {
      await this.pref.put('peer_pwd_' + cleanId, pwd);
    } else {
      await this.pref.delete('peer_pwd_' + cleanId);
    }
    await this.pref.flush();
  }

  public async removePeerPassword(id: string): Promise<void> {
    if (!this.pref) {
      return;
    }
    const cleanId = id.replace(/\s+/g, '');
    await this.pref.delete('peer_pwd_' + cleanId);
    await this.pref.flush();
  }
}
