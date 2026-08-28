/// 思考过程状态（产品：思考中 / 思考完成）。
enum ThinkingStatus { idle, thinking, done }

extension ThinkingStatusX on ThinkingStatus {
  bool get isActive => this != ThinkingStatus.idle;
  bool get isThinking => this == ThinkingStatus.thinking;
}
