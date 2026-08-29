import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../services/ai_client.dart';
import '../theme/fold_decoration.dart';
import '../theme/mode_theme.dart';
import '../widgets/buttons/pill_button.dart';

/// 各模式的危险色（与设置页一致：删除、危险操作）。
Color _modeDanger(ModeTheme mode) {
  switch (mode.view) {
    case BattleView.love:
      return const Color(0xFFB5543F); // 为爱：暖陶红
    case BattleView.right:
      return const Color(0xFFC4645A); // 论对错：暗金红
    case BattleView.win:
      return const Color(0xFFE5484D); // 比输赢：纯红
  }
}

/// 配置 AI 接口页（设置页「配置 API」push 的全屏页，产品文档 3.1.2）。
///
/// 本期只支持小米 MiMo（mimo-v2.5-pro），可选 OpenAI / Anthropic 兼容协议；
/// 填写 API Key 后可「测试连接」，保存后写入本地仓库供分析 / 记忆生成调用。
class AiConfigScreen extends ConsumerStatefulWidget {
  const AiConfigScreen({super.key});

  @override
  ConsumerState<AiConfigScreen> createState() => _AiConfigScreenState();
}

class _AiConfigScreenState extends ConsumerState<AiConfigScreen> {
  late AiProtocol _protocol;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _baseUrlController;
  bool _obscureKey = true;

  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(aiConfigProvider).valueOrNull ?? const AiConfig();
    _protocol = config.protocol;
    _apiKeyController = TextEditingController(text: config.apiKey);
    _modelController = TextEditingController(text: config.model);
    _baseUrlController = TextEditingController(text: config.baseUrl);
    _loadSavedConfig();
  }

  Future<void> _loadSavedConfig() async {
    final saved = await ref.read(appRepositoryProvider).watchAiConfig().first;
    if (!mounted) return;
    setState(() {
      _protocol = saved.protocol;
      _apiKeyController.text = saved.apiKey;
      _modelController.text = saved.model;
      _baseUrlController.text = saved.baseUrl;
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  AiConfig _buildConfig() {
    final apiKey = _apiKeyController.text.trim();
    return AiConfig(
      provider: AiProvider.xiaomi,
      protocol: _protocol,
      apiKey: apiKey,
      model: _modelController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      enabled: apiKey.isNotEmpty,
    );
  }

  /// 切换协议：若接口地址还是上一个协议的默认地址（或为空），跟随换成新默认。
  void _selectProtocol(AiProtocol next) {
    if (next == _protocol) return;
    final previousDefault = AiConfig(
      provider: AiProvider.xiaomi,
      protocol: _protocol,
    ).defaultBaseUrl;
    final current = _baseUrlController.text.trim();
    setState(() {
      _protocol = next;
      if (current.isEmpty || current == previousDefault) {
        _baseUrlController.text = AiConfig(
          provider: AiProvider.xiaomi,
          protocol: next,
        ).defaultBaseUrl;
      }
    });
  }

  Future<void> _testConnection() async {
    final config = _buildConfig();
    if (!config.isConfigured) {
      setState(() {
        _testing = false;
        _testOk = false;
        _testResult = '请先填写 API Key。';
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final reply = await const AiClient().ping(config);
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = true;
        _testResult = '连接成功：$reply';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = false;
        _testResult = '连接失败：$error';
      });
    }
  }

  Future<void> _save() async {
    final config = _buildConfig();
    try {
      await ref.read(repositoryActionsProvider).saveAiConfig(config);
      ref.invalidate(aiConfigProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(config.isConfigured ? '已保存配置' : '已清空配置（未填写 API Key）'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('保存失败，请稍后重试。'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ModeThemes.of(ref.watch(selectedBattleViewProvider));
    final draft = _buildConfig();
    final defaultUrl = draft.defaultBaseUrl;

    return Theme(
      data: mode.themeData,
      child: Scaffold(
        backgroundColor: mode.background,
        body: Stack(
          children: [
            Positioned.fill(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 130, 16, 150),
                children: [
                  _ProviderCard(mode: mode),
                  const SizedBox(height: 18),
                  _SectionLabel(
                    mode: mode,
                    icon: Icons.sync_alt_outlined,
                    text: '兼容协议',
                  ),
                  const SizedBox(height: 8),
                  _ProtocolSelector(
                    mode: mode,
                    selected: _protocol,
                    onSelect: _selectProtocol,
                  ),
                  const SizedBox(height: 18),
                  _SectionLabel(
                    mode: mode,
                    icon: Icons.key_outlined,
                    text: 'API Key',
                  ),
                  const SizedBox(height: 8),
                  _ConfigField(
                    mode: mode,
                    controller: _apiKeyController,
                    hint: 'sk-xxxxx',
                    obscure: _obscureKey,
                    onToggleObscure: () =>
                        setState(() => _obscureKey = !_obscureKey),
                  ),
                  const SizedBox(height: 18),
                  _SectionLabel(
                    mode: mode,
                    icon: Icons.auto_awesome_outlined,
                    text: '模型',
                  ),
                  const SizedBox(height: 8),
                  _ConfigField(
                    mode: mode,
                    controller: _modelController,
                    hint: '留空使用默认 mimo-v2.5',
                  ),
                  const SizedBox(height: 18),
                  _SectionLabel(
                    mode: mode,
                    icon: Icons.link_outlined,
                    text: '接口地址',
                  ),
                  const SizedBox(height: 8),
                  _ConfigField(
                    mode: mode,
                    controller: _baseUrlController,
                    hint: defaultUrl,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '切换协议时自动带入对应默认地址，可手动修改。',
                    style: TextStyle(color: mode.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 20),
                  _TestConnectionTile(
                    mode: mode,
                    testing: _testing,
                    result: _testResult,
                    ok: _testOk,
                    onTap: _testConnection,
                  ),
                  const SizedBox(height: 14),
                  _SaveButton(mode: mode, onTap: _save),
                  const SizedBox(height: 10),
                  Text(
                    '数据只发给你选择的模型厂商，不经过任何第三方。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mode.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            // 顶部渐隐：内容滚动到浮层标题下方时过渡淡出。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 110,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        mode.background.withValues(alpha: 1),
                        mode.background.withValues(alpha: 0.9),
                        mode.background.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.6, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // 底部渐变遮罩。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 120,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        mode.background.withValues(alpha: 1),
                        mode.background.withValues(alpha: 0.85),
                        mode.background.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // 顶部浮层：返回 + 标题 + 配置状态。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 16, 6),
                  child: Row(
                    children: [
                      PillButton(
                        mode: mode,
                        icon: Icons.arrow_back_rounded,
                        label: '',
                        highlight: true,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '配置 AI 接口',
                        style: TextStyle(
                          color: mode.text,
                          fontSize: 20,
                          fontWeight: mode.strongWeight,
                        ),
                      ),
                      const Spacer(),
                      _ConfigStatus(mode: mode, configured: draft.isConfigured),
                    ],
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

/// 顶部状态：已配置（主色圆点）/ 未配置。
class _ConfigStatus extends StatelessWidget {
  const _ConfigStatus({required this.mode, required this.configured});

  final ModeTheme mode;
  final bool configured;

  @override
  Widget build(BuildContext context) {
    final color = configured ? mode.primary : mode.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          configured ? '已配置' : '未配置',
          style: TextStyle(color: mode.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

/// 厂商卡片：本期固定小米 MiMo。
class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.mode});

  final ModeTheme mode;

  @override
  Widget build(BuildContext context) {
    return CutBox(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      fold: mode.cornerFold,
      color: mode.cardBackground,
      borderRadius: mode.cardRadius,
      border: Border.all(color: mode.cardBorder, width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: mode.cardShadowAlpha),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: mode.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 19,
              color: mode.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '小米 MiMo',
                      style: TextStyle(
                        color: mode.cardTitle,
                        fontSize: 15,
                        fontWeight: mode.strongWeight,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: mode.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'mimo-v2.5',
                        style: TextStyle(
                          color: mode.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '本期支持 · 更多厂商后续接入',
                  style: TextStyle(color: mode.cardMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 协议选择：OpenAI 兼容 / Anthropic 兼容 二选一。
class _ProtocolSelector extends StatelessWidget {
  const _ProtocolSelector({
    required this.mode,
    required this.selected,
    required this.onSelect,
  });

  final ModeTheme mode;
  final AiProtocol selected;
  final ValueChanged<AiProtocol> onSelect;

  static const _options = [
    (AiProtocol.openai, 'OpenAI 兼容', Icons.hexagon_rounded),
    (AiProtocol.anthropic, 'Anthropic 兼容', Icons.auto_awesome_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _options.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _ProtocolOption(
              mode: mode,
              icon: _options[i].$3,
              label: _options[i].$2,
              isSelected: _options[i].$1 == selected,
              onTap: () => onSelect(_options[i].$1),
            ),
          ),
        ],
      ],
    );
  }
}

class _ProtocolOption extends StatelessWidget {
  const _ProtocolOption({
    required this.mode,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final ModeTheme mode;
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? mode.primary : mode.cardBackground,
      shape: FoldShape(borderRadius: mode.chipRadius, fold: mode.cornerFold),
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? mode.onPrimary : mode.cardMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? mode.onPrimary : mode.cardBody,
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 区块小标题（协议 / API Key / 模型 / 接口地址）。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.mode,
    required this.icon,
    required this.text,
  });

  final ModeTheme mode;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: mode.textMuted),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            color: mode.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

/// 输入框：表面色底 + 模式圆角/切角，API Key 支持掩码切换。
class _ConfigField extends StatelessWidget {
  const _ConfigField({
    required this.mode,
    required this.controller,
    required this.hint,
    this.obscure,
    this.onToggleObscure,
  });

  final ModeTheme mode;
  final TextEditingController controller;
  final String hint;

  /// 非空时按掩码显示（如 API Key），并提供明文切换按钮。
  final bool? obscure;
  final VoidCallback? onToggleObscure;

  @override
  Widget build(BuildContext context) {
    return CutBox(
      fold: mode.cornerFold,
      color: mode.chipBackground,
      borderRadius: mode.inputRadius,
      border: Border.all(color: mode.chipBorder),
      child: TextField(
        controller: controller,
        obscureText: obscure ?? false,
        style: TextStyle(color: mode.text, fontSize: 13.5),
        cursorColor: mode.primary,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: mode.textMuted, fontSize: 12),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 11,
          ),
          suffixIcon: obscure != null
              ? IconButton(
                  tooltip: obscure! ? '显示' : '隐藏',
                  icon: Icon(
                    obscure!
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 18,
                    color: mode.textMuted,
                  ),
                  onPressed: onToggleObscure,
                )
              : null,
        ),
      ),
    );
  }
}

/// 测试连接：按钮 + 结果反馈（成功用主色，失败用模式危险色）。
class _TestConnectionTile extends StatelessWidget {
  const _TestConnectionTile({
    required this.mode,
    required this.testing,
    required this.result,
    required this.ok,
    required this.onTap,
  });

  final ModeTheme mode;
  final bool testing;
  final String? result;
  final bool ok;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final resultColor = result == null
        ? null
        : (ok ? mode.primary : _modeDanger(mode));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: mode.chipBackground,
          shape: FoldShape(
            borderRadius: mode.chipRadius,
            side: BorderSide(color: mode.chipBorder, width: 1),
            fold: mode.cornerFold,
          ),
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
            onTap: testing ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (testing)
                    SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: mode.primary,
                      ),
                    )
                  else
                    Icon(
                      Icons.wifi_tethering_rounded,
                      size: 17,
                      color: mode.primary,
                    ),
                  const SizedBox(width: 7),
                  Text(
                    testing ? '测试中…' : '测试连接',
                    style: TextStyle(
                      color: mode.cardBody,
                      fontSize: 13.5,
                      fontWeight: mode.strongWeight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (result != null) ...[
          const SizedBox(height: 8),
          Text(
            result!,
            style: TextStyle(
              color: resultColor ?? mode.cardMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// 保存：主色填充（三模式绿 / 金 / 白底反色）。
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.mode, required this.onTap});

  final ModeTheme mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: mode.actionChipBackground,
      shape: FoldShape(borderRadius: mode.chipRadius, fold: mode.cornerFold),
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
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_rounded,
                size: 18,
                color: mode.actionChipForeground,
              ),
              const SizedBox(width: 7),
              Text(
                '保存',
                style: TextStyle(
                  color: mode.actionChipForeground,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
