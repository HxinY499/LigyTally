import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/appearance/appearance.dart';
import '../../../core/database/app_database.dart';
import '../../../core/location/location_service.dart';
import '../../../core/location/place_fix.dart';
import '../../../core/media/image_storage.dart';
import '../../../core/preferences/auto_location.dart';
import '../../../core/preferences/last_category.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ledger_date.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/image_backdrop.dart';
import '../../../shared/widgets/local_image.dart';
import '../../../shared/widgets/photo_viewer.dart';
import '../application/amount_expression.dart';
import '../application/providers.dart';
import 'location_name_dialog.dart';

class TransactionEditor extends ConsumerStatefulWidget {
  const TransactionEditor({super.key, this.existing, this.initialDate});

  final LedgerItem? existing;

  /// 新建时的预设记账日期。
  ///
  /// 从明细页某天的日卡头部点「+」进来时带上那一天，省得用户再选一次日期。
  /// 为 null 走「今天」。编辑已有账单时本参数无效——账单自身的日期才是准的。
  final DateTime? initialDate;

  @override
  ConsumerState<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends ConsumerState<TransactionEditor> {
  late final TextEditingController _noteController;

  /// 备注框焦点。聚焦 = 系统键盘接管输入，数字键盘该主动让位。
  final FocusNode _noteFocus = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _pendingImages = [];
  final List<TransactionImageEntry> _existingImages = [];
  final Set<String> _removedImageIds = {};
  final ScrollController _scrollController = ScrollController();

  /// 背板当前展示第几张图（多图时由 [_backdropTimer] 推着走）。
  int _backdropIndex = 0;
  Timer? _backdropTimer;

  /// 金额表达式（可含+ −），例如 "3.5+7"。展示与计算都基于它。
  String _amountExpr = '';
  late int _kind;
  String? _categoryId;
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;
  bool _prefilledCategory = false;
  PlaceFix? _place;
  bool _locationFetching = false;
  int _captureGen = 0;

  bool get _isEditing => widget.existing != null;

  double get _amountValue => AmountExpression.evaluate(_amountExpr);

  bool get _canSave => _amountValue > 0 && _categoryId != null;

  @override
  void initState() {
    super.initState();
    final transaction = widget.existing?.transaction;
    _kind = transaction?.kind ?? 0;
    _categoryId = transaction?.categoryId;
    _date = transaction == null
        ? dateOnly(widget.initialDate ?? DateTime.now())
        : dateFromKey(transaction.accountingDate);
    final occurred = transaction == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(transaction.occurredAt);
    _time = TimeOfDay.fromDateTime(occurred);
    _amountExpr = transaction == null
        ? ''
        : (transaction.amountCents / 100).toStringAsFixed(2);
    _noteController = TextEditingController(text: transaction?.note ?? '');
    _place = transaction == null ? null : PlaceFix.tryFrom(transaction);
    _noteFocus.addListener(() {
      if (mounted) setState(() {});
    });
    if (transaction != null) {
      Future<void>(() async {
        final images = await ref
            .read(databaseProvider)
            .imagesFor(transaction.id);
        if (mounted) {
          setState(() {
            _existingImages.addAll(images);
            _restartBackdropRotation();
          });
        }
      });
    } else {
      _scheduleAutoCapture();
    }
  }

  @override
  void dispose() {
    _captureGen++;
    _backdropTimer?.cancel();
    _noteController.dispose();
    _noteFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int get _visibleImageCount =>
      _existingImages
          .where((image) => !_removedImageIds.contains(image.id))
          .length +
      _pendingImages.length;

  /// 可以铺到页面背板上的图，顺序与图片面板一致（已有图在前，新选的在后）。
  ///
  /// 解码宽度压到 [_kBackdropDecodeWidth]：这一层会被高斯模糊 + 渐隐吃掉细节，
  /// 按原始分辨率解码只是白白占内存。已有图片走 [ImageStorage.resolveSyncPath]
  /// 的同步缓存，避免异步 resolve 让背板晚一帧闪进来。
  List<ImageProvider> get _backdropImages {
    final images = <ImageProvider>[];
    for (final image in _existingImages) {
      if (_removedImageIds.contains(image.id)) continue;
      final path = ImageStorage.resolveSyncPath(image.thumbnailPath);
      if (path != null) images.add(_resized(File(path)));
    }
    for (final image in _pendingImages) {
      images.add(_resized(File(image.path)));
    }
    return images;
  }

  ImageProvider _resized(File file) => ResizeImage(
    FileImage(file),
    width: _kBackdropDecodeWidth,
    allowUpscaling: false,
  );

  /// 贴纸上要摆出来的照片，顺序与图片面板一致（已有图在前，新选的在后）。
  ///
  /// 与 [_backdropImages] 同源但另走一份：背板要的是模糊后的色调，这里要的是
  /// 看得清的原样，两边的解码尺寸与容错表现都不一样，合并反而要处处分叉。
  List<Widget> _polaroidPhotos(ImageStorage storage) {
    final photos = <Widget>[];
    for (final image in _existingImages) {
      if (_removedImageIds.contains(image.id)) continue;
      photos.add(
        LocalImage(storage: storage, relativePath: image.thumbnailPath),
      );
    }
    for (final image in _pendingImages) {
      photos.add(
        Image.file(
          File(image.path),
          fit: BoxFit.cover,
          cacheWidth: _kPolaroidDecodeWidth,
        ),
      );
    }
    return photos;
  }

  /// 图片增删后重排背板轮播：只有一张不转，多张从第一张重新开始。
  ///
  /// 索引只增不回绕，取图时再对当前张数取模——这样删图导致张数变化时
  /// 也不会越界，不用在每个增删入口同步维护索引。
  void _restartBackdropRotation() {
    _backdropTimer?.cancel();
    _backdropTimer = null;
    _backdropIndex = 0;
    if (_visibleImageCount < 2) return;
    // 贴纸模式下没有背板可轮播，定时器只会每 4 秒白刷一次页面。
    // 本页是 push 出来的路由，设置页此刻不可能开着，读一次就够。
    if (ref.read(transactionImageStyleProvider) !=
        TransactionImageStyle.backdrop) {
      return;
    }
    _backdropTimer = Timer.periodic(_kBackdropRotateInterval, (_) {
      if (mounted) setState(() => _backdropIndex++);
    });
  }

  /// 新建账单时预选「上次在该收支类型下选的分类」。
  void _prefillLastCategory(List<CategoryEntry> categories) {
    if (_prefilledCategory || _isEditing || _categoryId != null) return;
    _prefilledCategory = true;
    final lastId = ref.read(lastCategoryProvider)[_kind];
    if (lastId == null) return;
    final exists = categories.any((c) => c.id == lastId && c.kind == _kind);
    if (exists) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _categoryId = lastId);
      });
    }
  }

  void _onCategorySelected(String id) {
    HapticFeedback.selectionClick();
    setState(() => _categoryId = id);
  }

  void _onKeypadInput(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      switch (key) {
        case 'back':
          if (_amountExpr.isNotEmpty) {
            _amountExpr = _amountExpr.substring(0, _amountExpr.length - 1);
          }
        case '+':
        case '-':
          if (_amountExpr.isEmpty) return;
          final last = _amountExpr[_amountExpr.length - 1];
          if (last == '+' || last == '-') {
            _amountExpr =
                _amountExpr.substring(0, _amountExpr.length - 1) + key;
          } else {
            _amountExpr += key;
          }
        case '.':
          // 当前数字段已有小数点则忽略。
          final seg = _currentSegment();
          if (!seg.contains('.')) {
            _amountExpr += _amountExpr.isEmpty ? '0.' : '.';
          }
        default:
          // 限制单段整数位与小数位。
          final seg = _currentSegment();
          if (seg.contains('.')) {
            final decimals = seg.split('.').last;
            if (decimals.length >= 2) return;
          } else if (seg.replaceAll('-', '').length >= 9) {
            return;
          }
          _amountExpr += key;
      }
    });
  }

  /// 长按退格：一次清空整个表达式。
  ///
  /// 输错一长串（`128.5+66`）时逐位点退格很折磨。用重一档的震动反馈
  /// 与单击区分开，让用户知道「这下是全清，不是删一位」。
  void _clearAmount() {
    if (_amountExpr.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _amountExpr = '');
  }

  /// 当前正在输入的数字段（最后一个运算符之后的部分）。
  String _currentSegment() {
    var idx = -1;
    for (var i = _amountExpr.length - 1; i >= 0; i--) {
      if (_amountExpr[i] == '+' || _amountExpr[i] == '-') {
        idx = i;
        break;
      }
    }
    return _amountExpr.substring(idx + 1);
  }

  /// 选图并加入待上传列表。相册一次可多选，相机一次只能拍一张。
  ///
  /// 不触发 setState——调用方决定刷新编辑器整体还是图片面板的局部状态。
  ///
  /// 返回**被丢掉的张数**。`limit` 只是给系统选择器的建议，并非所有平台都会
  /// 真的拦住，所以这里仍按剩余名额截断一次；调用方据此告诉用户多选的那几张
  /// 没被全部收下，否则用户会以为自己点漏了。
  Future<int> _pickImages(ImageSource source) async {
    final remaining = kMaxTransactionImages - _visibleImageCount;
    if (remaining <= 0) return 0;
    final List<XFile> picked;
    if (source == ImageSource.camera) {
      final shot = await _picker.pickImage(source: source, imageQuality: 100);
      picked = [?shot];
    } else {
      picked = await _picker.pickMultiImage(
        imageQuality: 100,
        limit: remaining,
      );
    }
    if (!mounted || picked.isEmpty) return 0;
    _pendingImages.addAll(picked.take(remaining));
    return picked.length > remaining ? picked.length - remaining : 0;
  }

  /// 图片面板里点「添加」：先选来源（拍照/相册），选完刷新面板。
  Future<void> _addImageFromSheet(StateSetter refreshSheet) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(FLucideIcons.camera),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(FLucideIcons.images),
              title: const Text('从相册选择（可多选）'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final dropped = await _pickImages(source);
    refreshSheet(() {});
    if (dropped > 0 && mounted) {
      showAppToast(
        context,
        message: '最多 $kMaxTransactionImages 张，有 $dropped 张没有添加',
      );
    }
  }

  /// 键盘顶栏的图片入口：底部弹出图片管理面板（增删图片）。
  /// 面板直接操作共享的 [_pendingImages] / [_removedImageIds]，
  /// 关闭后再刷新编辑器，更新顶栏缩略图与角标。
  Future<void> _showImageSheet() async {
    final storage = ref.read(imageStorageProvider);
    final colors = context.colors;
    final accent = _kind == 0 ? colors.expense : colors.income;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: context.radii.sheetTop),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final visibleExisting = [
            for (final image in _existingImages)
              if (!_removedImageIds.contains(image.id)) image,
          ];
          final count = visibleExisting.length + _pendingImages.length;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题栏：居中标题 + 右侧关闭。
                  SizedBox(
                    height: 32,
                    child: Stack(
                      children: [
                        Center(
                          child: Text(
                            '添加图片',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: colors.ink,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.pop(context),
                            child: Icon(
                              FLucideIcons.x,
                              size: 22,
                              color: colors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (var i = 0; i < visibleExisting.length; i++)
                        _SheetImageTile(
                          child: LocalImage(
                            storage: storage,
                            relativePath: visibleExisting[i].thumbnailPath,
                          ),
                          onTap: () => _openPhotoViewer(context, i),
                          onRemove: () => setSheetState(
                            () => _removedImageIds.add(visibleExisting[i].id),
                          ),
                        ),
                      for (var i = 0; i < _pendingImages.length; i++)
                        _SheetImageTile(
                          child: Image.file(
                            File(_pendingImages[i].path),
                            fit: BoxFit.cover,
                          ),
                          onTap: () => _openPhotoViewer(
                            context,
                            visibleExisting.length + i,
                          ),
                          onRemove: () =>
                              setSheetState(() => _pendingImages.removeAt(i)),
                        ),
                      if (count < kMaxTransactionImages)
                        _SheetAddTile(
                          onTap: () => _addImageFromSheet(setSheetState),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: context.radii.sheetAll,
                        ),
                      ),
                      child: Text(
                        '确认（$count/$kMaxTransactionImages）',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(_restartBackdropRotation);
  }

  /// 从图片面板点开某张图，进全屏查看器。
  ///
  /// 送进去的是原图而不是缩略图：缩略图只有 320px，双击放大后是一团马赛克。
  /// 已有图片拼绝对路径要过一次异步 resolve，所以在点击时才现算——面板每次
  /// 重建都预先把三张的路径都 resolve 一遍不值当。
  ///
  /// 顺序与面板里的排列一致（已有图在前，新选的在后），[index] 直接就是面板
  /// 里的位置；仍然夹一次 clamp，避免 await 期间图片被删导致越界。
  Future<void> _openPhotoViewer(BuildContext context, int index) async {
    final storage = ref.read(imageStorageProvider);
    final images = <ImageProvider>[];
    for (final image in _existingImages) {
      if (_removedImageIds.contains(image.id)) continue;
      images.add(FileImage(await storage.resolve(image.imagePath)));
    }
    for (final image in _pendingImages) {
      images.add(FileImage(File(image.path)));
    }
    if (!context.mounted || images.isEmpty) return;
    await showPhotoViewer(
      context,
      images: images,
      initialIndex: index.clamp(0, images.length - 1),
    );
  }

  /// 删除当前正在编辑的账单，成功后退回上一页。
  ///
  /// 之前删除只有「在明细列表长按那一行」一条路径：没有图标、没有 chevron、
  /// 也没有滑动露出的红块，等于藏起来了。想删的人会点进本页四处找，
  /// 找不到再退出去，最后以为这个应用不能删。列表长按保留，作为熟手的快捷方式。
  Future<void> _deleteTransaction() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showAppConfirmDialog(
      context,
      message: '确定要删除该条账单吗？删除后不可恢复',
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(ledgerServiceProvider).delete(existing);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError('删除失败：$error');
      }
    }
  }

  Future<void> _selectDate() async {
    final value = await showAppDatePicker(context, initial: _date);
    if (!mounted) return;
    if (value != null) setState(() => _date = dateOnly(value));
    // 浮层是 PopupRoute，关闭后会恢复焦点；本页常驻可编辑焦点只有备注，
    // 恢复失败时会落到备注并弹出系统键盘。等本帧恢复完成后再清掉。
    _clearFocusAfterPicker();
  }

  Future<void> _selectTime() async {
    final value = await showAppTimePicker(context, initial: _time);
    if (!mounted) return;
    if (value != null) setState(() => _time = value);
    _clearFocusAfterPicker();
  }

  void _clearFocusAfterPicker() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  bool get _isTodayDate {
    final now = DateTime.now();
    return _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
  }

  Future<void> _scheduleAutoCapture() async {
    await ref.read(autoLocationProvider.notifier).ready;
    if (!mounted) return;
    _maybeAutoCapture();
  }

  void _maybeAutoCapture() {
    if (_isEditing || _place != null || _locationFetching) return;
    if (!ref.read(autoLocationProvider)) return;
    if (!_isTodayDate) return;
    _captureLocation(silent: true);
  }

  Future<void> _captureLocation({required bool silent}) async {
    final gen = ++_captureGen;
    setState(() => _locationFetching = true);
    final result = await ref
        .read(locationServiceProvider)
        .capture(requestIfNeeded: !silent);
    if (!mounted || gen != _captureGen) return;
    setState(() {
      _locationFetching = false;
      if (result.place != null) _place = result.place;
    });
    if (result.place == null && !silent && result.error != null) {
      _showLocationError(result.error!);
    }
  }

  void _showLocationError(LocationCaptureError error) {
    final message = switch (error) {
      LocationCaptureError.serviceDisabled => '请先打开系统定位',
      LocationCaptureError.permissionDenied => '需要定位权限才能记录位置',
      LocationCaptureError.permissionDeniedForever => '定位权限被关闭，请在系统设置中开启',
      LocationCaptureError.timeout => '定位超时，请再试一次',
      LocationCaptureError.unavailable => '暂时无法获取位置',
    };
    _showError(message);
  }

  Future<void> _onLocationTap() async {
    if (_locationFetching) return;
    if (_place == null) {
      await _captureLocation(silent: false);
      return;
    }
    final initial = _place!.storedName ?? '';
    final edited = await showLocationNameDialog(context, initial: initial);
    if (!mounted) return;
    _clearFocusAfterPicker();
    if (edited == null || _place == null) return;
    setState(() => _place = _place!.withName(edited));
  }

  void _clearLocation() {
    _captureGen++;
    setState(() {
      _place = null;
      _locationFetching = false;
    });
  }

  /// 保存。[continueAfter] 为 true 时保存后不关闭页面，清空金额继续记账。
  Future<void> _save({bool continueAfter = false}) async {
    final amount = _amountValue;
    if (amount <= 0) {
      _showError('请输入正确的金额');
      return;
    }
    if (_categoryId == null) {
      _showError('请选择分类');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(ledgerServiceProvider)
          .save(
            existing: continueAfter ? null : widget.existing,
            kind: _kind,
            amountCents: (amount * 100).round(),
            categoryId: _categoryId!,
            accountingDate: _date,
            occurredAt: DateTime(
              _date.year,
              _date.month,
              _date.day,
              _time.hour,
              _time.minute,
            ),
            note: _noteController.text,
            place: _place,
            pendingImages: _pendingImages,
            existingImages: _existingImages,
            removedImageIds: _removedImageIds,
          );
      // 记住这次用的分类，下次新建同类账单预选。
      await ref
          .read(lastCategoryProvider.notifier)
          .remember(_kind, _categoryId!);
      if (!mounted) return;
      if (continueAfter) {
        HapticFeedback.mediumImpact();
        final keepPlace =
            _place != null &&
            DateTime.now().difference(_place!.capturedAt) <= kReuseFixMaxAge;
        setState(() {
          _saving = false;
          _amountExpr = '';
          _noteController.clear();
          _pendingImages.clear();
          _existingImages.clear();
          _removedImageIds.clear();
          if (!keepPlace) _place = null;
          _restartBackdropRotation();
        });
        showAppToast(
          context,
          message: '已保存，继续记下一笔',
          level: AppToastLevel.success,
        );
        if (!keepPlace) _maybeAutoCapture();
      } else {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError('保存失败：$error');
      }
    }
  }

  void _showError(String message) {
    showAppToast(context, message: message, level: AppToastLevel.error);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final database = ref.watch(databaseProvider);
    final storage = ref.watch(imageStorageProvider);
    // 收支语义色：支出红 / 收入绿，贯穿金额卡与键盘按键。
    final accent = _kind == 0 ? colors.expense : colors.income;
    // 金额卡的千分位跟随全局偏好，与明细页 / 统计页的 formatMoney 保持一致。
    final grouped = ref.watch(moneyGroupedProvider);
    // 背板与贴纸互斥，由设置页的偏好二选一；只算用得上的那份，
    // 另一份的解码是白花的内存。
    final useBackdrop =
        ref.watch(transactionImageStyleProvider) ==
        TransactionImageStyle.backdrop;
    // 多图时轮流当背板：索引由定时器推进，这里对当前张数取模。
    final backdrops = useBackdrop ? _backdropImages : const <ImageProvider>[];
    final backdrop = backdrops.isEmpty
        ? null
        : backdrops[_backdropIndex % backdrops.length];
    // 贴纸把所有图一次摊开，不跟着 _backdropIndex 走：它模拟的是几张实体照片，
    // 自己会动就不像贴上去的了。
    final polaroids = useBackdrop ? const <Widget>[] : _polaroidPhotos(storage);

    // 顶栏图片入口的缩略图：优先最新待上传，其次已有图片。
    Widget? imagePreview;
    if (_pendingImages.isNotEmpty) {
      imagePreview = Image.file(
        File(_pendingImages.last.path),
        fit: BoxFit.cover,
      );
    } else {
      TransactionImageEntry? lastExisting;
      for (final image in _existingImages) {
        if (!_removedImageIds.contains(image.id)) lastExisting = image;
      }
      if (lastExisting != null) {
        imagePreview = LocalImage(
          storage: storage,
          relativePath: lastExisting.thumbnailPath,
        );
      }
    }

    return Scaffold(
      // 这一页有自己的背板时，底色必须是**实色**，把全局壁纸挡在外面。
      //
      // 不这么做就会出现两张照片叠在一起：壁纸模式下 `colors.canvas` 是透明的
      // （让壁纸从页底透上来），而本页又在自己的 Stack 里铺了一张账单图——
      // 账单图的渐隐段本该化进页面底色，结果化进了另一张照片。
      //
      // 进了记一笔页就该以**这笔账自己的图**为准：壁纸是全局氛围，账单图是
      // 这一页的内容。没有背板可铺时（贴纸模式、或这笔账没配图）传 null，
      // 底色回落到 `canvas`，壁纸照常透上来，与其余页面一致。
      backgroundColor: backdrop == null ? null : colors.canvasBase,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ImageBackdrop(
            image: backdrop,
            blurSigma: ref.watch(backdropBlurProvider),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              // 键盘区显示与否由两个条件把关，各管一头，见 _NumericKeypad 类文档：
              // 备注没聚焦（要不要留）、剩余高度够不够（能不能留）。
              //
              // 页头已是滚动体内部的 sliver，量不到「页头之下还剩多少」，
              // 只能从整页高度里把页头静止高度与底部安全区一起减掉。
              final panelHeight =
                  constraints.maxHeight -
                  appHeaderRestingExtent(context) -
                  MediaQuery.paddingOf(context).bottom;
              return AppTopBar(
                backgroundColor: Colors.transparent,
                title: _isEditing ? '编辑账单' : '记一笔',
                controller: _scrollController,
                // 只有编辑既有账单时才有得删；新建态放一颗永远灰着的垃圾桶
                // 只会让人猜它什么时候能点。
                actions: _isEditing
                    ? [
                        AppHeaderAction(
                          icon: FLucideIcons.trash2,
                          tooltip: '删除账单',
                          onTap: _saving ? null : _deleteTransaction,
                        ),
                      ]
                    : null,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    sliver: SliverList.list(
                      children: [
                        // 图片贴纸摆在最上面：一进页面第一眼就能看见自己拍的
                        // 那张照片，这是它在本页唯一的作用。无图时整块不渲染，
                        // 布局与没有图片功能时完全一致。
                        if (polaroids.isNotEmpty) ...[
                          _PolaroidStack(
                            photos: polaroids,
                            onTapPhoto: (index) =>
                                _openPhotoViewer(context, index),
                          ),
                          const SizedBox(height: 4),
                        ],
                        // 收支开关与「分类」同行：它切的就是下面这张网格，
                        // 摆在一起从属关系自明，也省下独占一行的高度。
                        Row(
                          children: [
                            const _SectionTitle(title: '分类'),
                            const Spacer(),
                            _KindSwitch(
                              kind: _kind,
                              onChanged: (value) {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _kind = value;
                                  _categoryId = null;
                                  _prefilledCategory = false;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        StreamBuilder<List<CategoryEntry>>(
                          stream: database.watchCategories(_kind),
                          builder: (context, snapshot) {
                            final categories =
                                snapshot.data ?? const <CategoryEntry>[];
                            if (categories.isEmpty) {
                              return SizedBox(
                                height: 72,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: context.colors.primary,
                                  ),
                                ),
                              );
                            }
                            _prefillLastCategory(categories);
                            return _CategoryPicker(
                              categories: categories,
                              selectedId: _categoryId,
                              accent: accent,
                              onSelected: _onCategorySelected,
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
                // 金额显示 + 日期/时刻 + 备注/图片条 + 数字键盘合成一块常驻输入面板。
                bottom: SafeArea(
                  top: false,
                  child: _NumericKeypad(
                    showKeys:
                        !_noteFocus.hasFocus &&
                        panelHeight >= _NumericKeypad.heightWithKeys,
                    expression: _amountExpr,
                    noteFocus: _noteFocus,
                    amountValue: _amountValue,
                    kind: _kind,
                    grouped: grouped,
                    accent: accent,
                    canSave: _canSave,
                    saving: _saving,
                    noteController: _noteController,
                    date: _date,
                    time: _time,
                    onPickDate: _selectDate,
                    onPickTime: _selectTime,
                    place: _place,
                    locationFetching: _locationFetching,
                    onLocationTap: _onLocationTap,
                    onLocationClear: _clearLocation,
                    imageCount: _visibleImageCount,
                    imagePreview: imagePreview,
                    onImageTap: _showImageSheet,
                    onInput: _onKeypadInput,
                    onClear: _clearAmount,
                    onSave: _canSave && !_saving ? () => _save() : null,
                    onSaveContinue: _canSave && !_saving && !_isEditing
                        ? () => _save(continueAfter: true)
                        : null,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 背板图的解码宽度。模糊后细节全丢，再高只是多占内存。
const int _kBackdropDecodeWidth = 480;

/// 多图时每张背板停留的时长。
const _kBackdropRotateInterval = Duration(seconds: 4);

/// 贴纸里照片的解码宽度：照片区 72pt，按 3x 屏留到 216 已经够清晰。
/// 相册原图动辄几千像素宽，直接解码进来一张就是几十兆。
const int _kPolaroidDecodeWidth = 216;

/// 账单图片的「拍立得贴纸」：几张带白边的小照片微微歪着、向左错开摊成一把。
///
/// 与整页背板是二选一的关系（见 [TransactionImageStyle]）。背板经过高斯模糊
/// 与渐隐之后只剩一层认不出来源的色雾，用户感知到的是氛围而不是「我拍的那张
/// 照片」；贴纸走另一条路——清晰、有边界、可点开，情绪落点是「翻账本时夹着
/// 的照片」。两种都只为观感存在，不承担信息展示的职责。
///
/// 独占一行走布局流、不浮在分类网格上：贴纸压住任何一个分类格子都会吃掉它的
/// 点击区，而分类是本页唯一的必选项，不能为装饰让路。
class _PolaroidStack extends StatefulWidget {
  const _PolaroidStack({required this.photos, required this.onTapPhoto});

  final List<Widget> photos;

  /// 松手时打开全屏查看器，参数是抬起的那张在图片面板里的位置。
  ///
  /// 不是打开图片管理面板：看图和管图是两个意图，而贴纸整个存在的理由就是
  /// 「让人再看一眼这张照片」，中间插一层增删界面等于把它挡在门外。
  /// 增删仍走键盘区的相机入口。
  final ValueChanged<int> onTapPhoto;

  @override
  State<_PolaroidStack> createState() => _PolaroidStackState();
}

class _PolaroidStackState extends State<_PolaroidStack> {
  /// 当前被抬起的那张。null 表示手指没落在任何一张上（也包括没在按）。
  int? _lifted;

  /// 从左到右的倾角（弧度）。角度全一致会像印刷出来的图案，逐帧随机又会自己
  /// 抖，固定成手摆过的样子；最右那张压在最上面，倾角也最小，最像被摆正的主角。
  ///
  /// 取的是**末尾** n 个（见 build 里的 sublist），所以往前加值只影响张数多的
  /// 情形，少于原来三张时的样子逐字不变。长度必须等于 [kMaxTransactionImages]。
  static const _kTilts = [-0.18, 0.155, -0.14, 0.09, -0.035];

  /// 照片区边长。
  static const double _kPhoto = 72;

  /// 相框白边：下边故意比其余三边宽，这是拍立得的辨识特征，
  /// 少了它就只是一张加了白框的普通缩略图。
  static const _kFrame = EdgeInsets.fromLTRB(5, 5, 5, 13);

  /// 单张相框的尺寸，由 [_kPhoto] 加 [_kFrame] 得出（72+5+5 / 72+5+13）。
  /// 写成常量而不是现算，因为外框尺寸要靠它推导。
  static const double _kCardWidth = 82;
  static const double _kCardHeight = 90;

  /// 相邻两张的水平错位。
  ///
  /// 早先几张相框同心叠放、只差旋转角，相邻不到 7° 的角度差让下面那些只从边角
  /// 露出几像素白边——露出来的还是相框而不是照片，传好几张和传 1 张看起来
  /// 没有区别。错开小半张（40 约为相框宽的一半）每张才都露得出内容；
  /// 再小会退回一摞，再大就散成几张不相干的图。
  ///
  /// 满 5 张时整把宽 258（82 + 4×40 + 余量），窄到 320dp 的屏也放得下。
  static const double _kSpread = 40;

  /// 旋转余量。[Transform.rotate] 只改绘制不改布局，尺寸得手动留够。
  /// 最歪的一张是 [_kTilts] 的 0.18（约 10.3°），82×90 转过去包围盒约
  /// 97×104，四边各留 8 才不会被 [Stack] 裁掉角。
  static const double _kRotationMargin = 8;

  /// 抬起的位移。外框高度为它另留一份、静止时整把再下沉半份，
  /// 抬到顶也不会顶出 [Stack] 被裁掉。
  static const double _kLift = 12;

  List<Widget> get _shown => widget.photos.take(_kTilts.length).toList();

  double get _boxWidth =>
      _kCardWidth + (_shown.length - 1) * _kSpread + _kRotationMargin * 2;

  /// 横坐标 [dx] 处压在最上面的那张；落在空白处返回 null。
  ///
  /// 从末尾往回找：绘制顺序里后面的盖在前面之上，倒着取到的第一个命中项
  /// 就是肉眼看到的那张。
  int? _indexAt(double dx) {
    final count = _shown.length;
    final origin = (count - 1) / 2;
    final center = _boxWidth / 2;
    for (var i = count - 1; i >= 0; i--) {
      if ((dx - (center + (i - origin) * _kSpread)).abs() <= _kCardWidth / 2) {
        return i;
      }
    }
    return null;
  }

  void _liftAt(double dx) {
    final next = _indexAt(dx);
    if (next == _lifted) return;
    // 只在真的抬起某张时震一下：拨过空白不该也有反馈。
    if (next != null) HapticFeedback.selectionClick();
    setState(() => _lifted = next);
  }

  /// 松手：抬着谁就看谁。手指停在空白处则什么也不做。
  void _release() {
    final index = _lifted;
    setState(() => _lifted = null);
    if (index != null) widget.onTapPhoto(index);
  }

  void _cancel() {
    if (_lifted == null) return;
    setState(() => _lifted = null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shown = _shown;
    if (shown.isEmpty) return const SizedBox.shrink();
    // 后添加的照片摆在最右、盖在最上面，倾角也从数组末尾往回取。
    final tilts = _kTilts.sublist(_kTilts.length - shown.length);
    // 整把在外框里居中：最左那张往左推多少，最右那张就往右推多少。
    final origin = (shown.length - 1) / 2;
    // 被抬起的那张挪到最后画。它在一把里可能压在别人下面，只往上抬 12
    // 也就露出一条边，得整张浮到最前面才看得出是「把它抽出来了」。
    final order = [
      for (var i = 0; i < shown.length; i++)
        if (i != _lifted) i,
      ?_lifted,
    ];
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 按下即抬起，松手才打开：这样「点一张」和「按住左右拨」是同一套
        // 动作的两端，不用分别解释。
        onTapDown: (details) => _liftAt(details.localPosition.dx),
        onTapUp: (_) => _release(),
        onTapCancel: _cancel,
        // 横向拖走的是水平识别器，与外层 ListView 的纵向滚动在竞技场里按
        // 方向分胜负：横着拨是挑照片，竖着划仍然是滚页面。
        onHorizontalDragStart: (details) => _liftAt(details.localPosition.dx),
        onHorizontalDragUpdate: (details) => _liftAt(details.localPosition.dx),
        onHorizontalDragEnd: (_) => _release(),
        onHorizontalDragCancel: _cancel,
        child: SizedBox(
          width: _boxWidth,
          height: _kCardHeight + _kRotationMargin * 2 + _kLift,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final i in order)
                TweenAnimationBuilder<double>(
                  // 重排绘制顺序后元素是按位置复用的，没有 key 会让抬起动画
                  // 跟错张。
                  key: ValueKey(i),
                  tween: Tween(begin: 0, end: i == _lifted ? 1.0 : 0.0),
                  duration: const Duration(milliseconds: 260),
                  // 冲过头再回落，就是那下弹簧感；线性或 easeOut 都只是「移上去」。
                  curve: Curves.easeOutBack,
                  builder: (context, t, child) => Transform.translate(
                    offset: Offset(
                      (i - origin) * _kSpread,
                      _kLift / 2 - t * _kLift,
                    ),
                    child: Transform.rotate(
                      // 抬起时顺手摆正：像从一摞里抽出一张端到眼前看。
                      angle: tilts[i] * (1 - t),
                      child: Transform.scale(scale: 1 + t * 0.06, child: child),
                    ),
                  ),
                  child: _frame(shown[i], colors),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _frame(Widget photo, AppColors colors) => Container(
    padding: _kFrame,
    decoration: BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(3),
      boxShadow: colors.shadowCard,
    ),
    child: SizedBox(
      width: _kPhoto,
      height: _kPhoto,
      child: ClipRRect(borderRadius: BorderRadius.circular(2), child: photo),
    ),
  );
}

class _CategoryPicker extends ConsumerStatefulWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.accent,
    required this.onSelected,
  });

  final List<CategoryEntry> categories;
  final String? selectedId;

  /// 收支语义色：选中态的图标/文字用它，和金额卡、键盘保持一致。
  final Color accent;
  final ValueChanged<String> onSelected;

  @override
  ConsumerState<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends ConsumerState<_CategoryPicker> {
  static const _columns = 5;

  /// 手风琴模式：同一时间只允许一个一级分类展开。
  String? _expandedId;

  /// 每行最近一次展开过的一级分类 id（网格模式，key 为行号）。
  ///
  /// 收起后 [_expandedId] 变 null，但该行的面板必须继续留在树上、拿着原来的
  /// 二级分类数据，才能把收起动画播完，所以要单独记住"这行该给谁挂面板"。
  final Map<int, String> _rowPanelOwner = {};

  @override
  void initState() {
    super.initState();
    _expandedId = _parentIdOf(widget.selectedId);
  }

  @override
  void didUpdateWidget(covariant _CategoryPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换收支类型后选中项被清空，同时收起展开的一级分类。
    if (widget.selectedId == null && _expandedId != null) {
      _expandedId = null;
      _rowPanelOwner.clear();
    }
  }

  String? _parentIdOf(String? categoryId) {
    if (categoryId == null) return null;
    for (final category in widget.categories) {
      if (category.id == categoryId) {
        return category.level == 1 ? category.id : category.parentId;
      }
    }
    return null;
  }

  List<CategoryEntry> _childrenOf(String parentId) {
    return widget.categories
        .where((item) => item.parentId == parentId)
        .toList();
  }

  void _onParentTap(CategoryEntry parent, bool hasChildren, {int? rowIndex}) {
    // 一级分类本身就是可选中的：点击即选中；
    // 有二级分类时同时展开/收起，二级只是进一步的细选，可以不选。
    widget.onSelected(parent.id);
    if (!hasChildren) return;
    setState(() {
      _expandedId = _expandedId == parent.id ? null : parent.id;
      // 收起时也要记下来，面板才有数据播收起动画。
      if (rowIndex != null) _rowPanelOwner[rowIndex] = parent.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(categoryPickerLayoutProvider);
    final parents = widget.categories.where((item) => item.level == 1).toList();
    final selectedParentId = _parentIdOf(widget.selectedId);

    if (layout == CategoryPickerLayout.grid) {
      return _buildGrid(parents, selectedParentId);
    }
    return _buildList(parents, selectedParentId);
  }

  /// 列表模式：一级分类纵向排列，二级分类在所属一级下方原地展开。
  Widget _buildList(List<CategoryEntry> parents, String? selectedParentId) {
    return Column(
      children: [
        for (final parent in parents) ...[
          _ParentCategoryTile(
            key: ValueKey('cat-tile-${parent.id}'),
            category: parent,
            selected: parent.id == selectedParentId,
            expanded: _expandedId == parent.id,
            hasChildren: _childrenOf(parent.id).isNotEmpty,
            accent: widget.accent,
            onTap: () =>
                _onParentTap(parent, _childrenOf(parent.id).isNotEmpty),
          ),
          _ChildrenPanel(
            key: ValueKey('cat-panel-${parent.id}'),
            ownerId: parent.id,
            visible: _expandedId == parent.id,
            children: _childrenOf(parent.id),
            selectedId: widget.selectedId,
            accent: widget.accent,
            columns: _columns,
            indent: 16,
            onSelected: widget.onSelected,
          ),
        ],
      ],
    );
  }

  /// 网格模式：一级分类 5 列网格，二级分类面板插入在被展开项所在行的下方。
  ///
  /// 每行都固定挂一个面板槽（没有展开项时高度为 0），这样 [Column] 的孩子结构
  /// 不会随展开状态增删——否则后续孩子的位置整体偏移，Flutter 按下标复用
  /// Element 时会给面板重建State，展开动画会被跳过（直接就是展开态）。
  Widget _buildGrid(List<CategoryEntry> parents, String? selectedParentId) {
    final rows = <Widget>[];
    for (var rowIndex = 0; rowIndex * _columns < parents.length; rowIndex++) {
      final start = rowIndex * _columns;
      final rowParents = parents.sublist(
        start,
        start + _columns > parents.length ? parents.length : start + _columns,
      );
      // 该行要挂面板的一级分类：优先当前展开项，否则是刚被收起、正在播动画的那个。
      CategoryEntry? panelOwner;
      for (final parent in rowParents) {
        if (parent.id == _expandedId) panelOwner = parent;
      }
      if (panelOwner == null) {
        final remembered = _rowPanelOwner[rowIndex];
        for (final parent in rowParents) {
          if (parent.id == remembered) panelOwner = parent;
        }
      }
      rows.add(
        Row(
          key: ValueKey('cat-row-$rowIndex'),
          children: [
            for (var i = 0; i < _columns; i++)
              Expanded(
                child: i < rowParents.length
                    ? _ParentGridCell(
                        category: rowParents[i],
                        selected: rowParents[i].id == selectedParentId,
                        expanded: _expandedId == rowParents[i].id,
                        hasChildren: _childrenOf(rowParents[i].id).isNotEmpty,
                        accent: widget.accent,
                        onTap: () => _onParentTap(
                          rowParents[i],
                          _childrenOf(rowParents[i].id).isNotEmpty,
                          rowIndex: rowIndex,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      );
      rows.add(
        _ChildrenPanel(
          key: ValueKey('cat-panel-row-$rowIndex'),
          ownerId: panelOwner?.id,
          visible: panelOwner != null && _expandedId == panelOwner.id,
          children: panelOwner == null
              ? const <CategoryEntry>[]
              : _childrenOf(panelOwner.id),
          selectedId: widget.selectedId,
          accent: widget.accent,
          columns: _columns,
          onSelected: widget.onSelected,
        ),
      );
    }
    return Column(children: rows);
  }
}

/// 列表模式的一级分类行：无卡片，扁平的图标 + 名称，右侧箭头随展开旋转。
class _ParentCategoryTile extends StatelessWidget {
  const _ParentCategoryTile({
    super.key,
    required this.category,
    required this.selected,
    required this.expanded,
    required this.hasChildren,
    required this.accent,
    required this.onTap,
  });

  final CategoryEntry category;
  final bool selected;
  final bool expanded;
  final bool hasChildren;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? accent : colors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: context.radii.blockAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            CategoryIconView(
              iconKey: category.iconKey,
              color: color,
              size: 24,
              selected: selected,
            ),

            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? colors.ink : colors.muted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (hasChildren)
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: selected ? accent : colors.line,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 网格模式下的一级分类单元格：扁平图标 + 下方文字，无卡片；
/// 有二级分类时，图标右下角挂一个展开/收起的小角标。
class _ParentGridCell extends StatelessWidget {
  const _ParentGridCell({
    required this.category,
    required this.selected,
    required this.expanded,
    required this.hasChildren,
    required this.accent,
    required this.onTap,
  });

  final CategoryEntry category;
  final bool selected;
  final bool expanded;
  final bool hasChildren;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? accent : colors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: context.radii.blockAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 30,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  CategoryIconView(
                    iconKey: category.iconKey,
                    color: color,
                    size: 26,
                    selected: selected,
                  ),

                  if (hasChildren)
                    Positioned(
                      right: -2,
                      bottom: 0,
                      child: AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? accent : colors.line,
                          ),
                          child: const Icon(
                            Icons.expand_more_rounded,
                            size: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                color: selected ? colors.ink : colors.muted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 二级分类面板：白色圆角底+ 顶部指向所属一级分类的小尖角，
/// 展开/收起走高度 + 淡入的组合动画。
/// 二级分类面板：白色圆角底，展开/收起走高度 + 淡入的组合动画。
class _ChildrenPanel extends StatefulWidget {
  const _ChildrenPanel({
    super.key,
    required this.ownerId,
    required this.visible,
    required this.children,
    required this.selectedId,
    required this.accent,
    required this.columns,
    required this.onSelected,
    this.indent = 0,
  });

  /// 当前面板归属的一级分类 id。同一个面板槽换了归属时要重播展开动画。
  final String? ownerId;
  final bool visible;
  final List<CategoryEntry> children;
  final String? selectedId;
  final Color accent;
  final int columns;
  final ValueChanged<String> onSelected;

  /// 左侧缩进：列表模式用缩进体现层级。
  final double indent;

  @override
  State<_ChildrenPanel> createState() => _ChildrenPanelState();
}

class _ChildrenPanelState extends State<_ChildrenPanel>
    with SingleTickerProviderStateMixin {
  /// 必须在 [initState] 里建，不能靠 `late final` 的惰性初始化。
  ///
  /// 网格模式下每行都常挂一个面板槽，没展开的那些行 [build] 会因 children 为空
  /// 提前返回，`_controller` 一次都不会被读到。等页面销毁时 [dispose] 里那句
  /// `_controller.dispose()` 成了首次访问，才去构造 [AnimationController] ——
  /// 而它要通过 context 查 [TickerMode]，此时 element 已经 deactivate，直接断言失败。
  late final AnimationController _controller;

  late final Animation<double> _expand = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.15, 1, curve: Curves.easeOut),
    reverseCurve: const Interval(0.4, 1, curve: Curves.easeIn),
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 200),
      vsync: this,
      value: widget.visible ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant _ChildrenPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ownerChanged = widget.ownerId != oldWidget.ownerId;
    if (widget.visible == oldWidget.visible && !ownerChanged) return;

    if (!widget.visible) {
      _controller.reverse();
      return;
    }
    // 同一行内从A 换成 B：内容整块换掉，从 0 重新长出来才不会显得是硬切。
    if (ownerChanged) _controller.value = 0;
    _controller.forward();
    // 展开时把面板滚入可见区域，避免被键盘/底栏遮挡。
    if (widget.children.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (widget.children.isEmpty) {
      return const SizedBox(width: double.infinity, height: 0);
    }
    return SizeTransition(
      sizeFactor: _expand,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _fade,
        child: Padding(
          padding: EdgeInsets.only(left: widget.indent, bottom: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: context.radii.cardAll,
            ),
            child: Column(children: _childRows()),
          ),
        ),
      ),
    );
  }

  List<Widget> _childRows() {
    final rows = <Widget>[];
    for (
      var start = 0;
      start < widget.children.length;
      start += widget.columns
    ) {
      rows.add(
        Row(
          children: [
            for (var i = start; i < start + widget.columns; i++)
              Expanded(
                child: i < widget.children.length
                    ? _CategoryCell(
                        iconKey: widget.children[i].iconKey,
                        name: widget.children[i].name,
                        selected: widget.selectedId == widget.children[i].id,
                        accent: widget.accent,
                        onTap: () => widget.onSelected(widget.children[i].id),
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      );
    }
    return rows;
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

/// 支出/收入胶囊开关：滑块式白底选中块 + 收支语义色文字。
///
/// 刻意**不撑满一行**：它只是个二选一的类型开关，信息量远小于金额与分类网格。
/// 之前满宽 + 10px 竖向内距，视觉重量压过了真正的主角（金额），一进页面眼睛
/// 先被它抓住。改成 [_kHeight] 高、内容宽度的小胶囊，层级才回到
/// 「金额 > 分类 > 类型开关」。
///
/// 宽度由 [_kSegmentWidth] 定死、不做居中或拉伸 —— 摆在哪由调用方决定
/// （现在是「分类」标题行的右端）。自带 [Center] 会在 Row 里撑满剩余宽度。
class _KindSwitch extends StatelessWidget {
  const _KindSwitch({required this.kind, required this.onChanged});

  final int kind;
  final ValueChanged<int> onChanged;

  /// 胶囊总高。32 是「拇指还够点、又不抢戏」的平衡点；
  /// 配合 [_kSegmentWidth] 得到两枚 62x26 的小段。
  static const double _kHeight = 32;

  /// 单段宽度。两个中文字 + 呼吸空间，固定宽度让滑块位移距离恒定。
  static const double _kSegmentWidth = 62;

  static const double _kPadding = 3;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedColor = kind == 0 ? colors.expense : colors.income;
    return SizedBox(
      height: _kHeight,
      width: _kSegmentWidth * 2 + _kPadding * 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.line.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(_kHeight / 2),
        ),
        child: Stack(
          children: [
            // 滑块：一块白底在两段之间滑动。用位移而不是「两个段各自淡入淡出
            // 背景」，切换才有连贯的运动感，也不会在中途出现两块白。
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: kind == 0
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(_kPadding),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  width: _kSegmentWidth,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(
                      (_kHeight - _kPadding * 2) / 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: selectedColor.withValues(alpha: 0.16),
                        blurRadius: 5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                _KindSegment(
                  label: '支出',
                  color: colors.expense,
                  selected: kind == 0,
                  onTap: () => onChanged(0),
                ),
                _KindSegment(
                  label: '收入',
                  color: colors.income,
                  selected: kind == 1,
                  onTap: () => onChanged(1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 胶囊里的一段：只负责文字与点击，选中态的白底由 [_KindSwitch] 的滑块提供。
class _KindSegment extends StatelessWidget {
  const _KindSegment({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            style: TextStyle(
              fontSize: 13,
              height: 1.1,
              letterSpacing: 0.2,
              color: selected ? color : colors.inactive,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

/// 金额卡的测试入口。
///
/// [_AmountCard] 是私有的（不希望被别的页面误用），但它承载了几条容易回归的
/// 硬性行为——溢出往左裁、高度不随运算符变化、负数要有文字解释。
/// 这层薄壳只为 test/amount_card_test.dart 打开访问，不参与业务渲染。
@visibleForTesting
class AmountCardForTest extends StatelessWidget {
  const AmountCardForTest({
    super.key,
    required this.expression,
    required this.amountValue,
    required this.kind,
    this.grouped = true,
  });

  final String expression;
  final double amountValue;
  final int kind;
  final bool grouped;

  @override
  Widget build(BuildContext context) => _AmountCard(
    expression: expression,
    amountValue: amountValue,
    kind: kind,
    grouped: grouped,
  );
}

/// 输入面板顶部的金额显示条：只读展示，输入来自同一面板下方的数字键盘。
///
/// ## 形态：显示屏，不是卡片
///
/// 它曾是滚动区里一张独立的白底圆角卡（带语义色描边），因为孤悬在内容流中
/// 需要自证边界。现在它和日期条、备注、按键同属一块 [_NumericKeypad] 面板，
/// 再留圆角描边就成了「面板里套卡片」，视觉更碎。所以改成**通栏白条**：
/// 无圆角无描边，靠与下方 [AppColors.canvas] 灰底的色差自然分区，
/// 就是计算器「上显示屏、下键盘」的经典关系。
///
/// 描边原先还兼职「有值时点亮语义色」的反馈，去掉后由大数字本身和光标承担
/// ——它们本来就是语义色，反馈没有丢。
///
/// ## 层级：结果是主角，过程是配角
///
/// 旧版把 28px 大字给了**表达式**（过程）、12px 灰字给了**合计**（结果），
/// 而记账真正要确认的是「这笔到底多少钱」——重量分配是反的。
/// 现在含运算符时：表达式退到上方一行小字，合计升为大字主角；
/// 不含运算符时（绝大多数场景）仍是单行大字，**且总高与含运算符时一致**，
/// 靠固定 [_kBodyHeight] 撑住。高度一变，整块输入面板会随按键上下跳
/// （搬进面板前的后果是下面的分类网格跳，约束没变，只是代价更大了）。
///
/// ## 溢出：截头留尾，而不是省略号截尾
///
/// 金额从左往右输入，尾部是刚按下的那一位。旧版用 `TextOverflow.ellipsis`
/// 从尾部截，一长就变 `3.5+7+12+8…`——**新按的数字看不见了，光标还亮着**，
/// 输入反馈直接断掉。这里改用右对齐 + 单行 [SingleChildScrollView] 反向裁剪：
/// 超长时自然把左边挤出可视区，尾部与光标永远可见（同计算器的行为）。
class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.expression,
    required this.amountValue,
    required this.kind,
    required this.grouped,
  });

  final String expression;
  final double amountValue;
  final int kind;

  /// 是否千分位分组，跟随全局 `moneyGrouped` 偏好。
  final bool grouped;

  /// 主数字行的固定高度。锁死它，切换「有无运算符」时总高不变。
  /// 40 是 28px 大字（headlineMedium）加行高后的下限，不能再压。
  static const double _kBodyHeight = 40;

  /// 辅助行（表达式 / 提示语）固定高度，同样为了稳定总高。
  static const double _kHintHeight = 16;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amountColor = kind == 0 ? colors.expense : colors.income;
    final hasExpr = expression.isNotEmpty;
    final showEquals = AmountExpression.hasOperator(expression);
    // 负数（如 `5-8`）保存按钮本来就是灰的，但旧版界面不解释为什么。
    final isNegative = amountValue < 0;

    // 主行显示什么：有运算符时显示合计（结果），否则显示正在输入的数字。
    final mainText = showEquals
        ? _formatValue(amountValue)
        : (hasExpr
              ? AmountExpression.format(expression, grouped: grouped)
              : '');
    final mainColor = isNegative
        ? colors.expense
        : (hasExpr ? amountColor : colors.line);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 辅助行：表达式过程 / 负数提示 ──
          SizedBox(
            height: _kHintHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: isNegative
                  ? Text(
                      '金额需大于 0',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: colors.expense.withValues(alpha: 0.85),
                      ),
                    )
                  : (showEquals
                        ? Text(
                            AmountExpression.format(
                              expression,
                              grouped: grouped,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.1,
                              color: colors.muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          )
                        : const SizedBox.shrink()),
            ),
          ),
          // ── 主行：¥ + 大数字 + 光标 ──
          SizedBox(
            height: _kBodyHeight,
            child: Row(
              children: [
                Text(
                  '¥',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ScrollingAmount(
                    text: mainText,
                    placeholder: '0.00',
                    color: mainColor,
                    caretColor: amountColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 合计的展示格式：固定两位小数 + 千分位。
  String _formatValue(double value) {
    final fixed = value.toStringAsFixed(2);
    if (!grouped) return fixed;
    final negative = fixed.startsWith('-');
    final body = negative ? fixed.substring(1) : fixed;
    return '${negative ? '-' : ''}${AmountExpression.format(body)}';
  }
}

/// 金额主数字 + 紧跟其后的光标条，超长时向左溢出（尾部始终可见）。
///
/// 实现要点：外层 [SingleChildScrollView] 只用来做「反向裁剪」——
/// `reverse: true` 让滚动位置默认停在末尾，
/// `physics: NeverScrollableScrollPhysics` 禁掉手动滚动（金额不该被划走）。
/// 这样内容超宽时被裁掉的是**左边**，而不是尾部加省略号。
class _ScrollingAmount extends StatelessWidget {
  const _ScrollingAmount({
    required this.text,
    required this.placeholder,
    required this.color,
    required this.caretColor,
  });

  final String text;

  /// 空值时的占位数字（灰色）。
  final String placeholder;
  final Color color;
  final Color caretColor;

  @override
  Widget build(BuildContext context) {
    final isEmpty = text.isEmpty;
    final caret = Container(
      margin: const EdgeInsets.only(left: 3),
      width: 2,
      height: 26,
      decoration: BoxDecoration(
        color: caretColor,
        borderRadius: BorderRadius.circular(1),
      ),
    );
    final number = Text(
      isEmpty ? placeholder : text,
      maxLines: 1,
      softWrap: false,
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
        // 等宽数字 + 零字距：位数变化时数字不左右抖，也不显松散。
        letterSpacing: 0,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    // 空态：光标贴在 ¥ 之后（即占位数字之前）。
    // 旧版把光标放在灰色 `0.00` 右侧，暗示下一位落在 `0.00` 后面，
    // 但实际按 5 得到的是 `5` 而不是 `0.005`，位置与行为不符。
    if (isEmpty) {
      return Row(
        children: [
          caret,
          Flexible(child: number),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(children: [number, caret]),
    );
  }
}

/// 键盘上方的日期/时刻条：两枚并排的小胶囊，点击各自唤起选择器。
///
/// 原先它是滚动区里的「时间」卡片 + 今天/昨天快捷键，占掉近三行高度，
/// 而实际改动频率远低于金额和分类。现在挪到备注同一层的常驻面板顶部：
/// 日期始终可见、随手可改，又不再和分类网格争夺竖向空间。
/// 快捷键去掉了——默认就是今天，选别的日子走日历更直接。
class _DateTimeBar extends StatelessWidget {
  const _DateTimeBar({
    required this.date,
    required this.time,
    required this.onPickDate,
    required this.onPickTime,
    required this.place,
    required this.locationFetching,
    required this.onLocationTap,
    required this.onLocationClear,
  });

  final DateTime date;
  final TimeOfDay time;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final PlaceFix? place;
  final bool locationFetching;
  final VoidCallback onLocationTap;
  final VoidCallback onLocationClear;

  bool get _isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool get _isYesterday {
    final y = DateTime.now().subtract(const Duration(days: 1));
    return date.year == y.year && date.month == y.month && date.day == y.day;
  }

  /// 日期文案：今天/昨天直接说人话，其余显示「x 月 x 日 周x」，
  /// 跨年再补上年份，避免把上一年的账记到今年而不自知。
  String get _dateLabel {
    if (_isToday) return '今天';
    if (_isYesterday) return '昨天';
    final day = formatDay(date);
    if (date.year != DateTime.now().year) return '${date.year} 年 $day';
    return '$day ${formatWeekday(date)}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DateTimeChip(
          icon: FLucideIcons.calendarDays,
          label: _dateLabel,
          onTap: onPickDate,
        ),
        const SizedBox(width: 8),
        _DateTimeChip(
          icon: FLucideIcons.clock,
          label: _clock(time),
          onTap: onPickTime,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LocationChip(
            place: place,
            fetching: locationFetching,
            onTap: onLocationTap,
            onClear: onLocationClear,
          ),
        ),
      ],
    );
  }

  /// 固定 24 小时制，与时间选择器保持一致，避免跟随系统出现「下午 8:46」。
  static String _clock(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

/// 日期/时刻条右侧的位置胶囊：空着时点一下获取，有地点后点一下改名，叉掉清除。
class _LocationChip extends StatelessWidget {
  const _LocationChip({
    required this.place,
    required this.fetching,
    required this.onTap,
    required this.onClear,
  });

  final PlaceFix? place;
  final bool fetching;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasPlace = place != null;
    return Material(
      color: colors.surface,
      borderRadius: context.radii.chipAll,
      child: InkWell(
        onTap: fetching ? null : onTap,
        canRequestFocus: false,
        borderRadius: context.radii.chipAll,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
          child: Row(
            children: [
              if (fetching)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: colors.primary,
                  ),
                )
              else
                Icon(FLucideIcons.mapPin, size: 14, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fetching
                      ? '定位中'
                      : hasPlace
                      ? place!.displayName
                      : '位置',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    color: colors.ink,
                  ),
                ),
              ),
              if (hasPlace && !fetching)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 2),
                    child: Icon(FLucideIcons.x, size: 14, color: colors.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 日期/时刻胶囊：白底小药丸，图标 + 一行文字，整块可点。
class _DateTimeChip extends StatelessWidget {
  const _DateTimeChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      borderRadius: context.radii.chipAll,
      child: InkWell(
        onTap: onTap,
        // 胶囊本身不该进焦点树：否则 PopupRoute 关闭时会把焦点交回这里，
        // 重建后再落到旁边的备注 TextField，系统键盘跟着弹出。
        canRequestFocus: false,
        borderRadius: context.radii.chipAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: colors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 二级分类选项：与一级网格一致的「大图标 + 下方小文字」竖向小格子。
/// 二级分类单元格：扁平图标 + 文字。
/// 内置图标选中变色；自定义图片选中画描边（见 [CategoryIconView.selected]）。
class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.iconKey,
    required this.name,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String iconKey;
  final String name;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? accent : colors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: context.radii.blockAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryIconView(
              iconKey: iconKey,
              size: 24,
              color: color,
              selected: selected,
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                color: selected ? colors.ink : colors.muted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 图片面板里的已选图片瓷贴：88x88 圆角图 + 右上角黑色删除钮。
class _SheetImageTile extends StatelessWidget {
  const _SheetImageTile({
    required this.child,
    required this.onTap,
    required this.onRemove,
  });

  final Widget child;

  /// 点缩略图进全屏查看。删除钮是 [Stack] 里的兄弟节点且画在更上层，
  /// 不会被这层点击区吃掉。
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: ClipRRect(
                borderRadius: context.radii.blockAll,
                child: child,
              ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: context.colors.ink,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  FLucideIcons.x,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 图片面板里的「添加」占位瓷贴。
class _SheetAddTile extends StatelessWidget {
  const _SheetAddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: context.radii.blockAll,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          // canvasBase：这是卡内一个凹槽，不是页底。
          color: colors.canvasBase,
          borderRadius: context.radii.blockAll,
        ),
        child: Center(
          child: Icon(FLucideIcons.camera, size: 26, color: colors.muted),
        ),
      ),
    );
  }
}

/// 面板中部的备注输入框：唤起系统键盘，面板整体被顶上去，数字键盘同时收起。
///
/// 键盘右下角固定为「完成」（[TextInputAction.done]）而不是换行——备注是单行，
/// 且这是收起系统键盘、让数字键盘和保存键回来的主出口。次出口是点金额显示条。
/// 没有出口的话，用户打完备注得先在面板外找地方点一下才能保存。
class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final border = OutlineInputBorder(
      borderRadius: context.radii.blockAll,
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      maxLength: 200,
      maxLines: 1,
      style: TextStyle(fontSize: 14, color: colors.ink),
      decoration: InputDecoration(
        hintText: '点击填写备注',
        hintStyle: TextStyle(fontSize: 14, color: colors.muted),
        filled: true,
        fillColor: colors.surface,
        counterText: '',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border,
      ),
    );
  }
}

/// 键盘顶栏的图片入口：无图显示相机图标，有图显示最新缩略图 + 张数角标。
class _ImageEntry extends StatelessWidget {
  const _ImageEntry({
    required this.count,
    required this.preview,
    required this.onTap,
  });

  final int count;
  final Widget? preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 46,
        height: 46,
        child: preview == null
            ? Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: context.radii.blockAll,
                ),
                child: Icon(FLucideIcons.camera, size: 20, color: colors.muted),
              )
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: context.radii.blockAll,
                      child: preview,
                    ),
                  ),
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 底部常驻输入面板：金额显示条 + 日期/时刻条 + 备注/图片条 + 数字键盘。
///
/// 金额显示与键盘本是一个逻辑控件，早期却被拆在页面两端（金额卡在滚动区顶部、
/// 键盘钉在底部），眼睛要在屏幕上下两头来回跑才能确认「按下去的数字进了哪」。
/// 现在合成一块：显示条通栏白底当「显示屏」，其余部分灰底当「键盘」，
/// 输入与反馈落在同一个拇指可达的区域内。
///
/// 固定高度布局（不用纵向 Expanded）——它被放在 Column 里、高度约束无界，
/// 用 Expanded 会因无法确定高度而崩溃。每行固定 [_keyHeight]。
/// 数字键盘常驻、不随金额输入消失；记账场景常见「多笔相加」，加减直接在键盘算，
/// 显示条实时给出合计。按键强调色跟随收支类型（支出红 / 收入绿）。
///
/// 键盘区（[showKeys]）由调用方用两个条件把关，缺一不可：
///
/// 1. **备注没聚焦**——聚焦时输入已被系统键盘接管，数字键盘不但用不上，
///    还会把分类网格挤没。这条管「要不要留」，是体验。
/// 2. **剩余高度 >= [heightWithKeys]**——面板在 Column 里是固定高度，
///    上方 `Expanded` 收缩到 0 之后无处可让，装不下就是 RenderFlex overflow。
///    这条管「能不能留」，是正确性。
///
/// 少了第 1 条，大屏上（系统键盘吃掉 300 后仍然装得下）两套键盘会同时堆在
/// 屏幕上。少了第 2 条，失焦的瞬间键盘区会立刻装回来，而此时系统键盘还在
/// 下滑、空间尚未归还，小屏上那一帧就是黄黑条。
///
/// 高度判断刻意落在「装不装得下」而不是「系统键盘是否弹起」：前者与布局同帧
/// 成立，后者要追 viewInsets 的变化时序，中间必然出现「空间已经变小、键盘区
/// 还没撤」的帧。也因此收起过程不能加高度动画——动画的中间高度同样会撞上限。
class _NumericKeypad extends StatelessWidget {
  const _NumericKeypad({
    required this.showKeys,
    required this.noteFocus,
    required this.expression,
    required this.amountValue,
    required this.kind,
    required this.grouped,
    required this.accent,
    required this.canSave,
    required this.saving,
    required this.noteController,
    required this.date,
    required this.time,
    required this.onPickDate,
    required this.onPickTime,
    required this.place,
    required this.locationFetching,
    required this.onLocationTap,
    required this.onLocationClear,
    required this.imageCount,
    required this.imagePreview,
    required this.onImageTap,
    required this.onInput,
    required this.onClear,
    required this.onSave,
    required this.onSaveContinue,
  });

  /// 是否渲染数字键盘区。见类文档里的两个把关条件。
  final bool showKeys;

  /// 备注框的焦点。挂到 [_NoteField] 上，供上层判断是否该收起键盘区。
  final FocusNode noteFocus;

  /// 金额表达式原文（可含 + −），交给显示条排版。
  final String expression;

  /// 表达式求值结果，含运算符时作为主数字显示。
  final double amountValue;

  /// 收支类型：0 支出 / 1 收入。显示条按它取语义色。
  final int kind;

  /// 是否千分位分组，跟随全局 `moneyGrouped` 偏好。
  final bool grouped;

  /// 收支语义色：支出红 / 收入绿，用于符号键与保存键。
  final Color accent;
  final bool canSave;
  final bool saving;
  final TextEditingController noteController;
  final DateTime date;
  final TimeOfDay time;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;
  final PlaceFix? place;
  final bool locationFetching;
  final VoidCallback onLocationTap;
  final VoidCallback onLocationClear;
  final int imageCount;

  /// 顶栏图片入口的缩略图（无图时为 null，显示相机图标）。
  final Widget? imagePreview;
  final VoidCallback onImageTap;
  final ValueChanged<String> onInput;

  /// 长按退格键：清空整个金额表达式。
  final VoidCallback onClear;
  final VoidCallback? onSave;
  final VoidCallback? onSaveContinue;

  static const double _keyHeight = 52;
  static const double _gap = 6;

  /// 键盘区自身的高度：4 行按键 + 3 道行距 + 底部留白。
  static const double _keysHeight = _keyHeight * 4 + _gap * 3 + 10;

  /// 面板去掉键盘区后的高度：显示条 72 + 日期条约 38 + 备注行 62。
  ///
  /// 日期胶囊的高度由文字度量决定、不是写死的，所以这里取的是含余量的估值；
  /// 估小了会导致「判断说装得下、实际差几个像素」，因此宁可往大了算。
  static const double _panelBaseHeight = 180;

  /// 完整面板（含键盘区）需要的高度。低于它就必须收起键盘区，
  /// 否则 Column 溢出。test/transaction_editor_test.dart 锁住这条。
  static const double heightWithKeys = _panelBaseHeight + _keysHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        // canvasBase：常驻输入面板必须是实底。它压在账单图片背板之上，
        // 半透明会让数字键盘上浮着一张照片。
        color: colors.canvasBase,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 金额显示屏。整条可点 = 收起系统键盘，让数字键盘回来——
          // 备注打完字后回到记账主流程的最短路径，也强化「显示条属于输入面板」。
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: _AmountCard(
              expression: expression,
              amountValue: amountValue,
              kind: kind,
              grouped: grouped,
            ),
          ),
          // 日期 / 时刻：放在备注上方，与输入区同层，随手可改。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: _DateTimeBar(
              date: date,
              time: time,
              onPickDate: onPickDate,
              onPickTime: onPickTime,
              place: place,
              locationFetching: locationFetching,
              onLocationTap: onLocationTap,
              onLocationClear: onLocationClear,
            ),
          ),
          // 备注输入 + 图片入口。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: _NoteField(
                    controller: noteController,
                    focusNode: noteFocus,
                  ),
                ),
                const SizedBox(width: 10),
                _ImageEntry(
                  count: imageCount,
                  preview: imagePreview,
                  onTap: onImageTap,
                ),
              ],
            ),
          ),
          if (showKeys) _keys(),
        ],
      ),
    );
  }

  /// 数字键盘区。空间不够时整块从面板里摘掉，理由见类文档。
  Widget _keys() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _keyRow(const ['7', '8', '9', 'back']),
          const SizedBox(height: _gap),
          _keyRow(const ['4', '5', '6', '-']),
          const SizedBox(height: _gap),
          _keyRow(const ['1', '2', '3', '+']),
          const SizedBox(height: _gap),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: _keyHeight,
                  child: _AgainKey(onTap: onSaveContinue),
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: SizedBox(
                  height: _keyHeight,
                  child: _NumKey(value: '0', onTap: () => onInput('0')),
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: SizedBox(
                  height: _keyHeight,
                  child: _NumKey(value: '.', onTap: () => onInput('.')),
                ),
              ),
              const SizedBox(width: _gap),
              Expanded(
                child: SizedBox(
                  height: _keyHeight,
                  child: _SaveKey(
                    accent: accent,
                    enabled: canSave,
                    loading: saving,
                    onTap: onSave,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _keyRow(List<String> keys) {
    return Row(
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          Expanded(
            child: SizedBox(
              height: _keyHeight,
              child: _NumKey(
                value: keys[i],
                symbolColor: accent,
                onTap: () => onInput(keys[i]),
                // 只有退格键支持长按全清。
                onLongPress: keys[i] == 'back' ? onClear : null,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 单个数字/符号/退格键（白底瓷键）。填满父级给定的固定高度。
class _NumKey extends StatelessWidget {
  const _NumKey({
    required this.value,
    required this.onTap,
    this.symbolColor,
    this.onLongPress,
  });

  final String value;
  final VoidCallback onTap;

  /// 符号键（+ −）文字色：跟随收支语义色。
  final Color? symbolColor;

  /// 长按回调。目前只有退格键用它做「一次清空」。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isBack = value == 'back';
    final isSymbol = value == '+' || value == '-';
    return Material(
      color: colors.surface,
      borderRadius: context.radii.blockAll,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: context.radii.blockAll,
        child: Center(
          child: isBack
              ? Icon(FLucideIcons.delete, size: 22, color: colors.ink)
              : Text(
                  value == '-' ? '−' : value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isSymbol
                        ? (symbolColor ?? colors.primary)
                        : colors.ink,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 左下「再记一笔」键：保存后不关页面，清空继续记。不可用时置灰。
class _AgainKey extends StatelessWidget {
  const _AgainKey({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Material(
      color: colors.surface,
      borderRadius: context.radii.blockAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radii.blockAll,
        child: Center(
          child: Text(
            '再记一笔',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: enabled ? colors.muted : colors.line,
            ),
          ),
        ),
      ),
    );
  }
}

/// 右下「保存」键：可用时收支语义色填充，不可用置灰。填满父级固定高度。
class _SaveKey extends StatelessWidget {
  const _SaveKey({
    required this.accent,
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final Color accent;
  final bool enabled;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: enabled ? accent : colors.surface,
      borderRadius: context.radii.blockAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radii.blockAll,
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  '保存',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: enabled ? Colors.white : colors.muted,
                  ),
                ),
        ),
      ),
    );
  }
}
