import { http } from '@kit.NetworkKit';
import { ConfigManager, UserProfile } from './ConfigStorage';

export interface LoginResult {
  success: boolean;
  message: string;
  user?: UserProfile;
}

export class AuthService {
  public static async login(
    account: string,
    password: string,
    apiServerOverride?: string
  ): Promise<LoginResult> {
    if (!account.trim() || !password.trim()) {
      return { success: false, message: '账号或密码不能为空' };
    }

    const configManager = ConfigManager.getInstance();
    let apiServer = apiServerOverride?.trim() ?? '';
    if (!apiServer) {
      const serverConfig = await configManager.getServerConfig();
      apiServer = serverConfig.apiServer.trim();
    }

    if (!apiServer) {
      // Default to official API or notify user to set custom server
      apiServer = 'https://api.rustdesk.com';
    }

    if (!apiServer.startsWith('http://') && !apiServer.startsWith('https://')) {
      apiServer = 'http://' + apiServer;
    }

    const url = `${apiServer}/api/login`;
    const httpRequest = http.createHttp();

    try {
      const payload = JSON.stringify({
        username: account.trim(),
        password: password.trim(),
        id: await configManager.getMyId(),
        uuid: 'ohos_' + (await configManager.getMyId())
      });

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        extraData: payload,
        connectTimeout: 8000,
        readTimeout: 8000
      });

interface LoginResponseUser {
  name?: string;
  email?: string;
  avatar?: string;
}

interface LoginResponseBody {
  access_token?: string;
  token?: string;
  username?: string;
  email?: string;
  avatar?: string;
  user?: LoginResponseUser;
  error?: string;
}

      if (response.responseCode === 200) {
        const bodyStr = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
        const body: LoginResponseBody = JSON.parse(bodyStr) as LoginResponseBody;
        const token: string = body.access_token ?? body.token ?? '';
        const username: string = body.user?.name ?? body.username ?? account.trim();
        const email: string = body.user?.email ?? body.email ?? '';
        const avatar: string = body.user?.avatar ?? '';

        if (!token) {
          return {
            success: false,
            message: body.error ? String(body.error) : '登录响应缺少认证令牌'
          };
        }

        const profile: UserProfile = {
          username,
          email,
          token,
          avatar,
          isLoggedIn: true
        };

        await configManager.saveUserProfile(profile);
        return {
          success: true,
          message: '登录成功',
          user: profile
        };
      } else {
        let errDesc = `服务器返回状态码: ${response.responseCode}`;
        try {
          const bodyStr = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
          const body: LoginResponseBody = JSON.parse(bodyStr) as LoginResponseBody;
          if (body.error) {
            errDesc = String(body.error);
          }
        } catch {
          // Ignore JSON parse error on error response
        }
        return { success: false, message: errDesc };
      }
    } catch (err) {
      return {
        success: false,
        message: `无法连接到服务器 (${url}): ${err instanceof Error ? err.message : String(err)}`
      };
    } finally {
      httpRequest.destroy();
    }
  }

  public static async logout(): Promise<void> {
    const configManager = ConfigManager.getInstance();
    await configManager.clearUserProfile();
  }
}
