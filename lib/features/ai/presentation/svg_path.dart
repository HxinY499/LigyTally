import 'dart:math' as math;
import 'dart:ui';

// 这些常量就是 SVG 命令字母，改成驼峰反而要对着规范翻译一遍。
// ignore_for_file: constant_identifier_names

/// 解析只含一条 path 的品牌 SVG。
///
/// 模型下拉框要的是各家标志，不为此引入 flutter_svg。
Path parseSvgPath(String source) {
  final parser = _SvgPathParser(source);
  parser.parse();
  return parser.path;
}

class _SvgPathParser {
  _SvgPathParser(this.source);

  final String source;
  final Path path = Path();
  int index = 0;
  double x = 0;
  double y = 0;
  double startX = 0;
  double startY = 0;
  double controlX = 0;
  double controlY = 0;
  int command = -1;

  void parse() {
    while (true) {
      _skipSeparators();
      if (index >= source.length) return;
      final code = source.codeUnitAt(index);
      if (_isCommand(code)) {
        command = code;
        index++;
      } else if (command == -1) {
        throw FormatException('SVG path 开头不是命令：$source');
      } else if (command == _m) {
        command = _l;
      } else if (command == _M) {
        command = _L;
      }
      switch (command) {
        case _M:
        case _m:
          final absolute = command == _M;
          final nx = _number(absolute ? 0 : x);
          final ny = _number(absolute ? 0 : y);
          path.moveTo(nx, ny);
          x = nx;
          y = ny;
          startX = nx;
          startY = ny;
          controlX = nx;
          controlY = ny;
        case _L:
        case _l:
          final absolute = command == _L;
          final nx = _number(absolute ? 0 : x);
          final ny = _number(absolute ? 0 : y);
          path.lineTo(nx, ny);
          x = nx;
          y = ny;
          controlX = nx;
          controlY = ny;
        case _H:
        case _h:
          final nx = _number(command == _H ? 0 : x);
          path.lineTo(nx, y);
          x = nx;
          controlX = nx;
          controlY = y;
        case _V:
        case _v:
          final ny = _number(command == _V ? 0 : y);
          path.lineTo(x, ny);
          y = ny;
          controlX = x;
          controlY = ny;
        case _C:
        case _c:
          final absolute = command == _C;
          final x1 = _number(absolute ? 0 : x);
          final y1 = _number(absolute ? 0 : y);
          final x2 = _number(absolute ? 0 : x);
          final y2 = _number(absolute ? 0 : y);
          final nx = _number(absolute ? 0 : x);
          final ny = _number(absolute ? 0 : y);
          path.cubicTo(x1, y1, x2, y2, nx, ny);
          controlX = x2;
          controlY = y2;
          x = nx;
          y = ny;
        case _S:
        case _s:
          final absolute = command == _S;
          final x1 = 2 * x - controlX;
          final y1 = 2 * y - controlY;
          final x2 = _number(absolute ? 0 : x);
          final y2 = _number(absolute ? 0 : y);
          final nx = _number(absolute ? 0 : x);
          final ny = _number(absolute ? 0 : y);
          path.cubicTo(x1, y1, x2, y2, nx, ny);
          controlX = x2;
          controlY = y2;
          x = nx;
          y = ny;
        case _A:
        case _a:
          final rx = _number(0).abs();
          final ry = _number(0).abs();
          final angle = _number(0);
          final large = _flag();
          final sweep = _flag();
          final absolute = command == _A;
          final nx = _number(absolute ? 0 : x);
          final ny = _number(absolute ? 0 : y);
          _arcTo(rx, ry, angle, large, sweep, nx, ny);
          controlX = nx;
          controlY = ny;
          x = nx;
          y = ny;
        case _Z:
        case _z:
          path.close();
          x = startX;
          y = startY;
          controlX = x;
          controlY = y;
        default:
          throw FormatException('不支持的 SVG 命令 ${String.fromCharCode(command)}');
      }
    }
  }

  double _number(double origin) {
    _skipSeparators();
    final start = index;
    if (index < source.length) {
      final sign = source.codeUnitAt(index);
      if (sign == _plus || sign == _minus) index++;
    }
    var sawDigit = false;
    while (index < source.length && _isDigit(source.codeUnitAt(index))) {
      sawDigit = true;
      index++;
    }
    if (index < source.length && source.codeUnitAt(index) == _dot) {
      index++;
      while (index < source.length && _isDigit(source.codeUnitAt(index))) {
        sawDigit = true;
        index++;
      }
    }
    if (!sawDigit) {
      throw FormatException('SVG path 在 $start 处缺少数值');
    }
    if (index < source.length &&
        (source.codeUnitAt(index) == _e || source.codeUnitAt(index) == _E)) {
      index++;
      if (index < source.length) {
        final sign = source.codeUnitAt(index);
        if (sign == _plus || sign == _minus) index++;
      }
      while (index < source.length && _isDigit(source.codeUnitAt(index))) {
        index++;
      }
    }
    return origin + double.parse(source.substring(start, index));
  }

  bool _flag() {
    _skipSeparators();
    if (index >= source.length) {
      throw FormatException('SVG 弧线缺少标志');
    }
    final code = source.codeUnitAt(index);
    index++;
    if (code == _zero) return false;
    if (code == _one) return true;
    throw FormatException('SVG 弧线标志只能是 0 或 1');
  }

  void _skipSeparators() {
    while (index < source.length) {
      final code = source.codeUnitAt(index);
      if (code == _space ||
          code == _comma ||
          code == _tab ||
          code == _lf ||
          code == _cr) {
        index++;
        continue;
      }
      break;
    }
  }

  void _arcTo(
    double rx,
    double ry,
    double angleDeg,
    bool large,
    bool sweep,
    double x2,
    double y2,
  ) {
    if (x == x2 && y == y2) return;
    if (rx == 0 || ry == 0) {
      path.lineTo(x2, y2);
      return;
    }
    final phi = angleDeg * math.pi / 180;
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);
    final dx = (x - x2) / 2;
    final dy = (y - y2) / 2;
    final x1p = cosPhi * dx + sinPhi * dy;
    final y1p = -sinPhi * dx + cosPhi * dy;
    var rxSq = rx * rx;
    var rySq = ry * ry;
    final x1pSq = x1p * x1p;
    final y1pSq = y1p * y1p;
    final lambda = x1pSq / rxSq + y1pSq / rySq;
    if (lambda > 1) {
      final scale = math.sqrt(lambda);
      rx *= scale;
      ry *= scale;
      rxSq = rx * rx;
      rySq = ry * ry;
    }
    final numer = rxSq * rySq - rxSq * y1pSq - rySq * x1pSq;
    final denom = rxSq * y1pSq + rySq * x1pSq;
    final coef =
        (large == sweep ? -1 : 1) * math.sqrt(math.max(0, numer / denom));
    final cxp = coef * rx * y1p / ry;
    final cyp = coef * -ry * x1p / rx;
    final cx = cosPhi * cxp - sinPhi * cyp + (x + x2) / 2;
    final cy = sinPhi * cxp + cosPhi * cyp + (y + y2) / 2;

    double vectorAngle(double ux, double uy, double vx, double vy) {
      final dot = ux * vx + uy * vy;
      final length = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
      if (length == 0) return 0;
      var angle = math.acos((dot / length).clamp(-1.0, 1.0));
      if (ux * vy - uy * vx < 0) angle = -angle;
      return angle;
    }

    final theta1 = vectorAngle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
    var delta = vectorAngle(
      (x1p - cxp) / rx,
      (y1p - cyp) / ry,
      (-x1p - cxp) / rx,
      (-y1p - cyp) / ry,
    );
    if (!sweep && delta > 0) delta -= 2 * math.pi;
    if (sweep && delta < 0) delta += 2 * math.pi;

    final segments = math.max(1, (delta.abs() / (math.pi / 2)).ceil());
    final step = delta / segments;
    final tangent = 4 / 3 * math.tan(step / 4);
    var theta = theta1;
    for (var i = 0; i < segments; i++) {
      final cos1 = math.cos(theta);
      final sin1 = math.sin(theta);
      final next = theta + step;
      final cos2 = math.cos(next);
      final sin2 = math.sin(next);
      Offset map(double px, double py) {
        final sx = rx * px;
        final sy = ry * py;
        return Offset(
          cosPhi * sx - sinPhi * sy + cx,
          sinPhi * sx + cosPhi * sy + cy,
        );
      }

      final c1 = map(cos1 - tangent * sin1, sin1 + tangent * cos1);
      final c2 = map(cos2 + tangent * sin2, sin2 - tangent * cos2);
      final end = map(cos2, sin2);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
      theta = next;
    }
  }
}

bool _isCommand(int code) {
  return code == _M ||
      code == _m ||
      code == _L ||
      code == _l ||
      code == _H ||
      code == _h ||
      code == _V ||
      code == _v ||
      code == _C ||
      code == _c ||
      code == _S ||
      code == _s ||
      code == _A ||
      code == _a ||
      code == _Z ||
      code == _z;
}

bool _isDigit(int code) => code >= _zero && code <= _nine;

const _M = 0x4d;
const _m = 0x6d;
const _L = 0x4c;
const _l = 0x6c;
const _H = 0x48;
const _h = 0x68;
const _V = 0x56;
const _v = 0x76;
const _C = 0x43;
const _c = 0x63;
const _S = 0x53;
const _s = 0x73;
const _A = 0x41;
const _a = 0x61;
const _Z = 0x5a;
const _z = 0x7a;
const _plus = 0x2b;
const _minus = 0x2d;
const _dot = 0x2e;
const _comma = 0x2c;
const _space = 0x20;
const _tab = 0x09;
const _lf = 0x0a;
const _cr = 0x0d;
const _e = 0x65;
const _E = 0x45;
const _zero = 0x30;
const _one = 0x31;
const _nine = 0x39;
