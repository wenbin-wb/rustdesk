import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export interface ServerConfig {
  idServer: string;
  relayServer: string;
  apiServer: string;
  key: string;
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
}

export class ConfigManager {
  private static instance: ConfigManager | null = null;
  private pref: preferences.Preferences | null = null;
  private isInitialized: boolean = false;

  private constructor() {}

  public static getInstance(): ConfigManager {
    if (!ConfigManager.instance) {
      ConfigManager.instance = new ConfigManager();
    }
    return ConfigManager.instance;
  }

  public async init(context: common.Context): Promise<void> {
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

  public async getServerConfig(): Promise<ServerConfig> {
    if (!this.pref) {
      return { idServer: '', relayServer: '', apiServer: '', key: '' };
    }
    const idServer = (await this.pref.get('custom_rendezvous_server', '')) as string;
    const relayServer = (await this.pref.get('relay_server', '')) as string;
    const apiServer = (await this.pref.get('api_server', '')) as string;
    const key = (await this.pref.get('key', '')) as string;
    return { idServer, relayServer, apiServer, key };
  }

  public async saveServerConfig(config: ServerConfig): Promise<void> {
    if (!this.pref) {
      return;
    }
    await this.pref.put('custom_rendezvous_server', config.idServer.trim());
    await this.pref.put('relay_server', config.relayServer.trim());
    await this.pref.put('api_server', config.apiServer.trim());
    await this.pref.put('key', config.key.trim());
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
}
