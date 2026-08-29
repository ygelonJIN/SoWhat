import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../screens/memory_screen.dart';
import '../theme/fold_decoration.dart';
import '../theme/mode_theme.dart';
import '../utils/format.dart';
import '../widgets/battle/battle_canvas.dart';
import '../widgets/battle/image_fan_gallery.dart';
import '../widgets/buttons/pill_button.dart';
import '../widgets/feedback/feedback.dart';
import '../widgets/feedback/uploading_dialog.dart';
import '../widgets/input/chat_composer.dart';
import '../widgets/settings/settings_panel.dart';

/// 读取图片文件头几个字节，识别真实格式并返回后缀（.jpg / .png / .webp）。
///
/// 用 magic bytes 而不是扩展名判断，避免 image_picker 压缩转换后
/// 扩展名与内容不一致导致发给模型时类型标注错误。
Future<String> _detectImageExtension(String path) async {
  final raf = await File(path).open();
  try {
    final bytes = await raf.read(12);
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return '.jpg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return '.png';
    }
    if (bytes.length >= 12 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return '.webp';
    }
    return '.jpg';
  } finally {
    await raf.close();
  }
}

/// 按文件后缀映射 MIME 类型（暂存文件后缀由 [_detectImageExtension] 保证
/// 与真实格式一致）。
String _mimeTypeFor(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

/// 在后台 isolate 里把图片解码并重编码为 JPEG q90（与实测选定的
/// 「JPEG q90 全分辨率」一致）。返回 null 表示无法解码（如 HEIC），
/// 调用方应保留原图。
Uint8List? _encodeJpeg90(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return img.encodeJpg(decoded, quality: 90);
  } catch (_) {
    return null;
  }
}

/// 主聊天界面（产品文档 3.1）。
///
/// 「全屏聊天 + 浮层控制」：顶部设置/日期、模式切换、输入框都悬浮在聊天
/// 内容上方。点左上角「设置」后整页右移，只留原本左侧 1/4 可见，左侧 3/4
/// 展开设置页（搜索框 / 新建对话 / 聊天记录）。
class BattleScreen extends ConsumerStatefulWidget {
  const BattleScreen({super.key});

  @override
  ConsumerState<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends ConsumerState<BattleScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();

  final _fanGalleryKey = GlobalKey<ImageFanGalleryState>();
  final _inputFocusNode = FocusNode();
  bool _isFanPeeked = false;
  bool _keyboardVisible = false;
  bool _settingsOpen = false;

  /// 底部模式选择器是否处于展开态（点旁边空白处 / 选中后自动收起）。
  bool _modeExpanded = false;

  /// 暂存的待发送图片（选图后先挂在这里，点「发送」才写入对话并发给模型）。
  /// 三个模式共用同一批暂存图片：发送后当前模式不再显示（见
  /// [_stagedImagesConsumedBy]），其他模式仍可见可发。
  final List<String> _stagedImages = [];

  /// 已「消费」过当前暂存图片的模式：在该模式下点过发送后，这个模式的扇面
  /// 不再显示这批图片，但图片仍保留在暂存区供其他模式复用；三个模式都发送
  /// 过后自动清空暂存（图片随发送进入对话历史，不再常驻扇面）。
  final Set<BattleView> _stagedImagesConsumedBy = {};

  /// 正在选图/压缩（防止连点附着按钮重复弹出系统相册）。
  bool _pickingImages = false;

  /// 当前打开的对话 id（设置页切换对话 / 新建对话时变化）。
  /// 首帧前可能尚未解析（provider 初始为 null），返回空串让界面先渲染空态，
  /// [ensureConversation] 完成后会自动重建。
  String get _conversationId => ref.read(selectedConversationIdProvider) ?? '';

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(_handleInputFocusChanged);
    // 首帧先解析当前对话（最近的聊天记录，没有则新建一段空白对话）；
    // 再恢复该对话保存的模式，不自动触发思考。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrapConversation();
    });
  }

  /// 启动时创建一段「临时空白对话」作为当前对话（可正常编辑发送）；
  /// 顺带清理上次退出时残留的空白对话，让空白草稿只在作为当前对话时短暂存在。
  Future<void> _bootstrapConversation() async {
    try {
      final actions = ref.read(repositoryActionsProvider);
      final id = await actions.ensureConversation();
      if (!mounted) return;
      await actions.cleanupStaleEmptyConversations(keepConversationId: id);
      if (!mounted) return;
      _restoreConversationMode(_conversationId);
    } catch (e, st) {
      // 启动阶段失败不阻塞界面，后续交互时再重试；但必须打到日志，
      // 否则启动期数据库异常会表现为只转圈、终端无报错。
      debugPrint('[BattleScreen] 启动对话初始化失败: $e\n$st');
    }
  }

  @override
  void dispose() {
    _inputFocusNode.removeListener(_handleInputFocusChanged);
    _inputFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleInputFocusChanged() {
    if (!mounted) return;
    final visible = _inputFocusNode.hasFocus;
    if (visible != _keyboardVisible) {
      setState(() => _keyboardVisible = visible);
    }
  }

  /// 点聊天空白处：收起键盘，若扇面处于放大态则同时缩回最小态，
  /// 并收起底部展开的模式选项。
  void _dismissKeyboardAndCollapseFan() {
    if (_keyboardVisible) {
      FocusScope.of(context).unfocus();
    }
    _collapseFan();
    if (_modeExpanded) {
      setState(() => _modeExpanded = false);
    }
  }

  void _onFanPeekChanged(bool peeked) {
    if (mounted && _isFanPeeked != peeked) {
      setState(() => _isFanPeeked = peeked);
    }
  }

  void _collapseFanOnScroll() {
    _collapseFan();
  }

  void _collapseFan() {
    if (_isFanPeeked) {
      _fanGalleryKey.currentState?.collapse();
      setState(() => _isFanPeeked = false);
    }
  }

  // ─── 设置页（左侧 3/4 面板） ───────────────────────────────────────────────

  void _openSettings() {
    if (_settingsOpen) return;
    FocusScope.of(context).unfocus();
    _collapseFan();
    setState(() => _settingsOpen = true);
  }

  void _closeSettings() {
    if (!_settingsOpen) return;
    FocusScope.of(context).unfocus();
    setState(() => _settingsOpen = false);
  }

  // ─── 记忆档案（独立全屏页） ───────────────────────────────────────────────

  void _openMemory() {
    FocusScope.of(context).unfocus();
    _collapseFan();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MemoryScreen()));
  }

  Future<void> _createNewConversation() async {
    try {
      final actions = ref.read(repositoryActionsProvider);
      // 先清掉当前打开的空白草稿对话（没有任何消息），避免「新建」时
      // 上一个空白对话残留在历史记录里被反复累积。
      if (_conversationId.isNotEmpty) {
        await actions.cleanupEmptyConversation(_conversationId);
      }
      final caseItem = await actions.createConversation();
      ref.read(selectedConversationIdProvider.notifier).state = caseItem.id;
      _closeSettings();
    } catch (e, st) {
      // 透出真实错误，定位数据库初始化失败原因
      // ignore: avoid_print
      print('[BattleScreen] _createNewConversation error: $e\n$st');
      _showError('新建对话失败：$e');
    }
  }

  void _selectConversation(String conversationId) {
    if (conversationId == _conversationId) {
      _closeSettings();
      return;
    }
    ref.read(selectedConversationIdProvider.notifier).state = conversationId;
    _closeSettings();
  }

  Future<void> _onConversationChanged(String? previousId) async {
    FocusScope.of(context).unfocus();
    _collapseFan();
    // 切换对话：空白草稿只在当前页面临时存在，离开后从历史记录中消失、
    // 也不写入长期记忆（空白对话没有任何消息，天然不产生分析卡片）。
    if (previousId != null && mounted) {
      await ref
          .read(repositoryActionsProvider)
          .cleanupEmptyConversation(previousId);
    }
    // 切换对话时不取消后台分析；每个对话和模式的任务彼此独立并行运行。
    if (_stagedImages.isNotEmpty || _stagedImagesConsumedBy.isNotEmpty) {
      setState(() {
        _stagedImages.clear();
        _stagedImagesConsumedBy.clear();
      });
    }
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _restoreConversationMode(_conversationId);
  }

  /// 每个对话隔离：切换到某段对话时，恢复它自己保存的模式（为爱 / 论对错 / 比输赢）。
  Future<void> _restoreConversationMode(String conversationId) async {
    try {
      final cases = await ref.read(casesProvider.future);
      Case? caseItem;
      for (final item in cases) {
        if (item.id == conversationId) {
          caseItem = item;
          break;
        }
      }
      if (!mounted) return;
      if (ref.read(selectedConversationIdProvider) != conversationId) return;
      if (caseItem != null) {
        ref.read(selectedBattleViewProvider.notifier).state = caseItem.lastView;
        ref
            .read(repositoryActionsProvider)
            .syncThinkingToView(conversationId, caseItem.lastView);
      }
    } catch (_) {
      // 读取失败保持当前模式即可。
    }
  }

  // ─── 对话操作 ───────────────────────────────────────────────────────────────

  /// 清除暂存的图片（点扇面展开后的 ✕）；尚未发送，不触碰对话数据。
  void _clearStagedImages() {
    _collapseFan();
    if (_stagedImages.isEmpty && _stagedImagesConsumedBy.isEmpty) return;
    setState(() {
      _stagedImages.clear();
      _stagedImagesConsumedBy.clear();
    });
    ref.read(debugStatusProvider.notifier).state = '已清除暂存图片';
  }

  /// 发送：文字 + 暂存图片一起写入对话，并触发分析（图片此时才真正发给模型）。
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final analysisView = ref.read(selectedBattleViewProvider);
    // 当前模式已经发送过这批图片（已作为消息进入对话）时，不再重复写入，
    // 避免同一批图在对话里堆积重复消息；尚未发送的模式照常发出。
    final imagesToSend = _stagedImagesConsumedBy.contains(analysisView)
        ? const <String>[]
        : List<String>.unmodifiable(_stagedImages);
    final hasImages = imagesToSend.isNotEmpty;
    if (text.isEmpty && !hasImages) return;
    try {
      // 允许并行分析：不再先取消上一轮分析。
      ref.read(debugStatusProvider.notifier).state = hasImages
          ? '发送文字 + ${imagesToSend.length} 张图片…'
          : '发送消息并触发分析…';
      if (text.isNotEmpty) {
        await ref
            .read(repositoryActionsProvider)
            .addMessage(
              conversationId: _conversationId,
              party: Party.a,
              content: text,
            );
      }
      for (var i = 0; i < imagesToSend.length; i++) {
        final assetPath = imagesToSend[i];
        final file = File(assetPath);
        final asset = Asset(
          path: assetPath,
          title: '',
          sizeBytes: await file.length(),
          mimeType: _mimeTypeFor(assetPath),
        );
        final existingAsset = await ref
            .read(appRepositoryProvider)
            .assetByPath(assetPath);
        await ref.read(appRepositoryProvider).saveAsset(existingAsset ?? asset);
        await ref
            .read(repositoryActionsProvider)
            .addMessage(
              conversationId: _conversationId,
              party: Party.a,
              type: MessageType.image,
              content: '截图 ${i + 1}',
              assetPath: assetPath,
            );
      }
      _messageController.clear();
      // 发送后：当前模式不再显示这批暂存图片（其他模式仍共享可见可发）；
      // 三个模式都发送过之后自动清空暂存，避免图片「永远存在」。
      // 只有这次真正把图片发出去才标记消费；纯文字发送不消耗图片。
      if (hasImages) {
        setState(() {
          _stagedImagesConsumedBy.add(analysisView);
          if (_stagedImagesConsumedBy.length >= BattleView.values.length) {
            _stagedImages.clear();
            _stagedImagesConsumedBy.clear();
          }
        });
      }
      unawaited(_runAnalysis(view: analysisView));
    } catch (_) {
      _showError('发送失败，请稍后重试。');
    }
  }

  /// 选图：只暂存，不写入对话、不触发分析；点「发送」才会发出。
  ///
  /// 图片没有固定张数上限；每张图片转成 Base64 后不能超过官方 50 MB 限制。
  /// 请求总大小还受接口和上下文限制影响，因此发送前会计算体积。
  ///
  /// 压缩策略：
  /// - image_picker 的 imageQuality: 90 只对 JPEG/HEIC 生效，PNG 会被原样
  ///   返回（已核实插件源码），所以 PNG（尤其截图）在这里用纯 Dart 解码
  ///   并重编码为 JPEG q90，与实测选定的压缩效果一致；
  /// - 已压缩的小体积 JPEG（≤2MB）直接使用，避免二次编码损耗。
  ///
  /// 图片多、压缩耗时可能较长：选图与压缩全程展示主题化「正在上传图片」
  /// 弹窗（进度条 + 张数提示），处理完自动收起。
  Future<void> _pickImages() async {
    if (_pickingImages) return;
    _pickingImages = true;
    final mode = ModeThemes.of(ref.read(selectedBattleViewProvider));
    final progress = ValueNotifier<UploadingProgress>(
      const UploadingProgress(done: 0, total: 0, stage: '正在打开相册…'),
    );
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final dialogRoute = DialogRoute<void>(
      context: context,
      builder: (_) => UploadingDialog(mode: mode, progress: progress),
      barrierDismissible: false,
      useSafeArea: true,
    );
    unawaited(rootNavigator.push(dialogRoute));

    // 只关闭上传弹窗本身：处理期间若有并行分析失败弹出了错误弹窗，
    // 不能直接 pop（会把顶层的错误弹窗关掉、上传弹窗残留卡住）。
    void closeUploadDialog() {
      if (dialogRoute.isActive && dialogRoute.navigator != null) {
        dialogRoute.navigator!.removeRoute(dialogRoute);
      }
    }

    try {
      ref.read(debugStatusProvider.notifier).state = '正在选择图片…';
      final images = await _imagePicker.pickMultiImage(imageQuality: 90);
      if (images.isEmpty) {
        closeUploadDialog();
        progress.dispose();
        ref.read(debugStatusProvider.notifier).state = '未选择图片';
        return;
      }
      final existing = _stagedImages.toSet();
      final added = <String>[];
      var skippedOversize = 0;
      final assetDirectory = await getApplicationDocumentsDirectory();
      final assetsDirectory = Directory(p.join(assetDirectory.path, 'assets'));
      await assetsDirectory.create(recursive: true);
      final total = images.length;
      for (var i = 0; i < images.length; i++) {
        final sourcePath = images[i].path;
        if (existing.contains(sourcePath)) {
          progress.value = UploadingProgress(
            done: i + 1,
            total: total,
            stage: '跳过重复图片 ${i + 1}/$total…',
          );
          continue;
        }
        progress.value = UploadingProgress(
          done: i,
          total: total,
          stage: '正在压缩图片 ${i + 1}/$total…',
        );
        // 官方限制：单张图片的 Base64 字符串不能超过 50 MB。
        final sourceFile = File(sourcePath);
        final base64Size = (await sourceFile.length() + 2) ~/ 3 * 4;
        if (base64Size > kMaxBase64ImageBytes) {
          skippedOversize++;
          continue;
        }
        var extension = await _detectImageExtension(sourcePath);
        var outputBytes = await sourceFile.readAsBytes();
        // PNG 或其他大文件需要压缩；已压缩的小 JPEG 直接用。
        final needsCompress =
            extension != '.jpg' || outputBytes.length > 2 * 1024 * 1024;
        if (needsCompress) {
          final compressed = await compute(_encodeJpeg90, outputBytes);
          if (compressed != null) {
            outputBytes = compressed;
            extension = '.jpg';
          }
        }
        final target = File(
          p.join(
            assetsDirectory.path,
            '${DateTime.now().microsecondsSinceEpoch}_${added.length}$extension',
          ),
        );
        await target.writeAsBytes(outputBytes, flush: true);
        added.add(target.path);
        existing.add(target.path);
        progress.value = UploadingProgress(
          done: added.length,
          total: total,
          stage: '已处理 ${added.length}/$total…',
        );
      }
      closeUploadDialog();
      progress.dispose();
      setState(() {
        _stagedImages.addAll(added);
        // 新一批图片对所有模式重新可见（都还没在该模式下发送过）。
        _stagedImagesConsumedBy.clear();
      });
      if (skippedOversize > 0) {
        _showSnackBar('有 $skippedOversize 张图片超过官方 50 MB Base64 限制，已跳过');
      }
      ref.read(debugStatusProvider.notifier).state =
          '已暂存 ${_stagedImages.length} 张图片（已压缩为 JPEG），点「发送」才真正发出';
    } catch (error) {
      closeUploadDialog();
      progress.dispose();
      _showError('截图导入失败，请检查相册权限。', error);
    } finally {
      _pickingImages = false;
    }
  }

  Future<void> _runAnalysis({required BattleView view}) async {
    final conversationId = _conversationId;
    if (conversationId.isEmpty) return;
    ref.read(debugStatusProvider.notifier).state = '正在准备分析…';
    try {
      final turnId = DateTime.now().millisecondsSinceEpoch.toString();
      final skipped = await ref
          .read(repositoryActionsProvider)
          .runAnalysis(conversationId, turnId: turnId, analysisView: view);
      if (skipped > 0 &&
          ref.read(selectedConversationIdProvider) == conversationId &&
          ref.read(selectedBattleViewProvider) == view) {
        _showThemedError(
          '有 $skipped 张图片已失效（文件不存在），本次分析已自动跳过这些图片。',
          ModeThemes.of(view),
        );
      }
    } catch (error) {
      // 无论用户当前停留在哪个模式，只要还在这段对话里就要让失败可见：
      // 否则切换到其他模式后，失败的思考框只会显示「思考完成」、没有任何
      // 输出也没有错误提示（静默失败）。
      if (ref.read(selectedConversationIdProvider) == conversationId) {
        ref.read(debugStatusProvider.notifier).state = '分析失败：$error';
        _showError('分析失败，请稍后重试。', error, ModeThemes.of(view));
      }
    }
  }

  void _showThemedError(String message, ModeTheme mode) {
    FeedbackDialog.error(context, mode, message);
  }

  Future<void> _selectView(BattleView view) async {
    if (view == ref.read(selectedBattleViewProvider)) return;
    if (_modeExpanded) {
      setState(() => _modeExpanded = false);
    }
    ref.read(selectedBattleViewProvider.notifier).state = view;
    ref
        .read(repositoryActionsProvider)
        .syncThinkingToView(_conversationId, view);
    try {
      await ref
          .read(repositoryActionsProvider)
          .setBattleView(_conversationId, view);
    } catch (error) {
      _showError('切换视角失败，请稍后重试。', error);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    final mode = ModeThemes.of(ref.read(selectedBattleViewProvider));
    FeedbackDialog.show(context, mode, message: message);
  }

  void _showError(String message, [Object? error, ModeTheme? viewMode]) {
    if (!mounted) return;
    final mode =
        viewMode ?? ModeThemes.of(ref.read(selectedBattleViewProvider));
    final detail = error == null ? message : '$message（$error）';
    _showThemedError(detail, mode);
  }

  // ─── 界面 ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selectedView = ref.watch(selectedBattleViewProvider);
    final mode = ModeThemes.of(selectedView);
    final conversationId = ref.watch(selectedConversationIdProvider);
    if (conversationId == null) {
      return Scaffold(
        backgroundColor: mode.background,
        body: Center(child: CircularProgressIndicator(color: mode.primary)),
      );
    }
    final battleAsync = ref.watch(
      battleStateProvider((conversationId: conversationId, view: selectedView)),
    );
    final messagesAsync = ref.watch(
      conversationMessagesProvider(conversationId),
    );
    final isAnalyzing = ref.watch(
      isAnalyzingProvider('$conversationId:${selectedView.name}'),
    );
    final conversationStartedAt =
        ref.watch(conversationStartedAtProvider(conversationId)).valueOrNull ??
        DateTime.now();

    ref.listen(selectedConversationIdProvider, (previous, next) {
      if (previous == next) return;
      _onConversationChanged(previous);
    });

    final messages = messagesAsync.valueOrNull ?? const [];
    // 扇面只展示「当前模式尚未发送」的暂存图片：点「发送」后这批图片进入
    // 对话历史、当前模式的扇面不再显示（其他模式仍共享可见可发）；三个模式
    // 都发送过后自动清空暂存。已发送进对话的图片不再常驻扇面。
    final showStagedImages =
        _stagedImages.isNotEmpty &&
        !_stagedImagesConsumedBy.contains(selectedView);
    final screenshotPaths = showStagedImages
        ? List<String>.unmodifiable(_stagedImages)
        : const <String>[];

    return Theme(
      data: mode.themeData,
      child: PopScope(
        canPop: !_settingsOpen,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _settingsOpen) _closeSettings();
        },
        child: Scaffold(
          body: AnnotatedRegion<SystemUiOverlayStyle>(
            value: mode.isDark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final settingsWidth = width * 0.75;

                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // 聊天主内容：设置展开时右移 75%，仅左侧 1/4 可见。
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 340),
                      curve: Curves.easeOutCubic,
                      left: _settingsOpen ? settingsWidth : 0,
                      top: 0,
                      bottom: 0,
                      width: width,
                      child: _buildBattleBody(
                        mode: mode,
                        selectedView: selectedView,
                        battleState:
                            battleAsync.valueOrNull ??
                            BattleState.initial(selectedView),
                        messages: messages,
                        screenshotPaths: screenshotPaths,
                        isAnalyzing: isAnalyzing,
                        conversationStartedAt: conversationStartedAt,
                      ),
                    ),
                    // 遮罩：盖住可见的聊天区，点击收起设置。
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !_settingsOpen,
                        child: AnimatedOpacity(
                          opacity: _settingsOpen ? 1 : 0,
                          duration: const Duration(milliseconds: 340),
                          curve: Curves.easeOutCubic,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _closeSettings,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.26),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 设置页（左侧 3/4），从左侧滑入。
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 340),
                      curve: Curves.easeOutCubic,
                      left: _settingsOpen ? 0 : -settingsWidth,
                      top: 0,
                      bottom: 0,
                      width: settingsWidth,
                      child: SettingsPanel(
                        mode: mode,
                        onClose: _closeSettings,
                        onNewConversation: _createNewConversation,
                        onSelectConversation: _selectConversation,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 聊天主内容（全屏聊天 + 浮层控制）的完整布局。
  Widget _buildBattleBody({
    required ModeTheme mode,
    required BattleView selectedView,
    required BattleState battleState,
    required List<Message> messages,
    required List<String> screenshotPaths,
    required bool isAnalyzing,
    required DateTime conversationStartedAt,
  }) {
    return Stack(
      children: [
        Positioned.fill(child: Container(color: mode.background)),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _dismissKeyboardAndCollapseFan,
            child: BattleCanvas(
              state: battleState,
              messages: messages,
              mode: mode,
              scrollController: _scrollController,
              onScroll: _collapseFanOnScroll,
            ),
          ),
        ),
        // 顶部遮罩：压在滚动内容之上，让从下方滚到顶部浮层（右上角日期、
        // 扇面）下的内容柔和淡出，与底部遮罩对称。
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 220,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    mode.background.withValues(alpha: 1.0),
                    mode.background.withValues(alpha: 0.9),
                    mode.background.withValues(alpha: 0.48),
                    mode.background.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.34, 0.72, 1.0],
                ),
              ),
            ),
          ),
        ),
        if (_isFanPeeked)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: const SizedBox.expand(),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _FloatingTopChrome(
                    mode: mode,
                    startedAt: conversationStartedAt,
                    onSettings: _openSettings,
                  ),
                  if (screenshotPaths.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        // 向右留出一点边距，让扇面整体往左移，不贴右缘。
                        padding: const EdgeInsets.only(right: 10),
                        child: ImageFanGallery(
                          key: _fanGalleryKey,
                          paths: screenshotPaths,
                          mode: mode,
                          onPeekChanged: _onFanPeekChanged,
                          onRemove: _clearStagedImages,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 176,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    mode.background.withValues(alpha: 1.0),
                    mode.background.withValues(alpha: 0.9),
                    mode.background.withValues(alpha: 0.48),
                    mode.background.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.34, 0.72, 1.0],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _ModeMemoryBar(
                        mode: mode,
                        selectedView: selectedView,
                        expanded: _modeExpanded,
                        onToggleExpanded: () =>
                            setState(() => _modeExpanded = !_modeExpanded),
                        onSelected: _selectView,
                        onMemory: _openMemory,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ChatComposer(
                    mode: mode,
                    controller: _messageController,
                    focusNode: _inputFocusNode,
                    onSend: _sendMessage,
                    onAttach: _pickImages,
                    onInputTap: _collapseFan,
                    isAnalyzing: false,
                    pendingCount: _stagedImages.length,
                    pendingAlreadySent: _stagedImagesConsumedBy.contains(
                      selectedView,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 浮动顶栏：左上角「设置」按钮（直接展开设置页，样式跟随当前选中的模式按钮），
/// 右上角本次对话开始时间。
class _FloatingTopChrome extends StatelessWidget {
  const _FloatingTopChrome({
    required this.mode,
    required this.startedAt,
    required this.onSettings,
  });

  final ModeTheme mode;
  final DateTime startedAt;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final start = startedAt;
    final date = '${formatDate(start)}  ${formatTime(start)}';

    return Row(
      children: [
        PillButton(
          mode: mode,
          icon: Icons.menu_rounded,
          label: '设置',
          highlight: true,
          onTap: onSettings,
        ),
        const Spacer(),
        PillButton(
          mode: mode,
          icon: Icons.calendar_today_rounded,
          label: date,
          compact: true,
        ),
      ],
    );
  }
}

/// 底部操作条：一行摆放「记忆 + 当前模式」两个同尺寸主色按钮；点击模式按钮
/// 向上展开另外两个模式（当前选中已显示在按钮上，不再重复展开），选中后收起；
/// 点展开区以外的空白处也会收起（由父级监听画布点击处理）。
/// 展开选项沿用旧的分段按钮样式（当前模式的未选中描边胶囊）。
/// 因父级 Column 底贴屏幕，展开内容整体向上顶开，不遮挡输入框。
class _ModeMemoryBar extends StatelessWidget {
  const _ModeMemoryBar({
    required this.mode,
    required this.selectedView,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onSelected,
    required this.onMemory,
  });

  final ModeTheme mode;
  final BattleView selectedView;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<BattleView> onSelected;
  final VoidCallback onMemory;

  static const _views = [BattleView.love, BattleView.right, BattleView.win];

  @override
  Widget build(BuildContext context) {
    final selected = selectedView;
    // 展开时只显示「另外两个」模式：当前选中的已展示在触发按钮上。
    final options = [
      for (final v in _views)
        if (v != selected) v,
    ];

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (expanded) ...[
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _ModeOptionButton(
                mode: mode,
                label: ModeThemes.of(options[i]).title,
                onTap: () => onSelected(options[i]),
              ),
            ],
            const SizedBox(height: 12),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PillButton(
                mode: mode,
                icon: Icons.auto_stories_rounded,
                label: '记忆',
                highlight: true,
                onTap: onMemory,
              ),
              const SizedBox(width: 10),
              // 当前模式按钮与「记忆」同款同尺寸。
              PillButton(
                mode: mode,
                icon: Icons.unfold_more_rounded,
                label: ModeThemes.of(selected).title,
                highlight: true,
                onTap: onToggleExpanded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 展开态单个模式选项：只显示「另外两个」模式，沿用旧分段按钮的未选中样式
/// （当前模式的表面色 + 描边 + 弱化文字，不套用其它模式的主题配色）。
class _ModeOptionButton extends StatelessWidget {
  const _ModeOptionButton({
    required this.mode,
    required this.label,
    required this.onTap,
  });

  final ModeTheme mode;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: mode.chipBackground,
      shape: FoldShape(
        borderRadius: mode.chipRadius,
        side: BorderSide(
          color: mode.chipBorder.withValues(alpha: 0.55),
          width: 1,
        ),
        fold: mode.cornerFold,
      ),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: mode.cornerFold ? null : mode.chipRadius,
        customBorder: mode.cornerFold
            ? FoldShape(
                borderRadius: BorderRadius.zero,
                side: BorderSide.none,
                fold: true,
              )
            : null,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: mode.chipForeground,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
