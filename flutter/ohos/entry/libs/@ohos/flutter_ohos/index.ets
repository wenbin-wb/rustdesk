import { UIAbility, common } from '@kit.AbilityKit';

export class BinaryMessenger {}

export class DartExecutor {
  getBinaryMessenger(): BinaryMessenger {
    return new BinaryMessenger();
  }
}

export class FlutterEngine {
  dartExecutor: DartExecutor = new DartExecutor();
}

export class MethodCall {
  method: string = '';
  args: Object | null = null;
  argument<T>(key: string): T | null {
    return null;
  }
}

export interface MethodResult {
  success(result: Object | null | undefined): void;
  error(errorCode: string, errorMessage?: string, errorDetails?: Object): void;
  notImplemented(): void;
}

export interface MethodCallHandler {
  onMethodCall(call: MethodCall, result: MethodResult): void;
}

export class MethodChannel {
  constructor(messenger: BinaryMessenger, name: string) {}
  setMethodCallHandler(handler: MethodCallHandler | null): void {}
  async invokeMethod(method: string, args?: Object): Promise<Object | null> {
    return null;
  }
}

export class FlutterAbility extends UIAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine): void {}
}

export { FlutterPage } from './FlutterPage';
