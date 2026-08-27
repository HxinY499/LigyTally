import 'package:flutter/services.dart';

const _channel = MethodChannel('com.ligy.ligy_tally/app_update');

/// 用系统浏览器打开 https 链接。
///
/// 走现有更新通道，不另加插件。失败返回 false，由界面提示。
Future<bool> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return false;
  try {
    await _channel.invokeMethod<void>('openUrl', {'url': url});
    return true;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
