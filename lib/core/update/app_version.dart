/// 语义化版本号，用于比较本地版本与 GitHub Release 上的版本。
///
/// 只处理 `major.minor.patch` 三段式，这也是 pubspec.yaml 里的写法。
/// 解析时容忍前缀 `v`（GitHub tag 惯例是 `v1.0.1`）以及
/// `1.0.1+2` 这种带 build number 的形式（`+` 之后的部分不参与比较，
/// 因为 versionCode 只对Android 覆盖安装有意义，不代表版本新旧）。
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// 解析失败返回 null，调用方据此静默跳过本次更新检查，
  /// 而不是抛异常打断启动流程。
  static AppVersion? tryParse(String? raw) {
    if (raw == null) return null;
    var text = raw.trim();
    if (text.isEmpty) return null;

    // 去掉 GitHub tag 惯用的 v 前缀
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    // 丢掉 build number 与预发布标记
    final plus = text.indexOf('+');
    if (plus != -1) text = text.substring(0, plus);
    final dash = text.indexOf('-');
    if (dash != -1) text = text.substring(0, dash);

    final parts = text.split('.');
    if (parts.isEmpty || parts.length > 3) return null;

    final numbers = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part.trim());
      // 任一段不是纯数字就认为格式不认识，不猜
      if (value == null || value < 0) return null;
      numbers.add(value);
    }
    // 允许 "1.0" 这种两段式，缺失位补 0
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return AppVersion(numbers[0], numbers[1], numbers[2]);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  String toString() => '$major.$minor.$patch';

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);
}
