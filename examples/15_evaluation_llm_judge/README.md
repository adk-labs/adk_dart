# 15. Agent Evaluation & Benchmarking

Demonstrates automated CI/CD evaluation, rubric-based LLM-as-a-Judge benchmarking, and trajectory analysis using `LocalEvalService` and `EvalCase`.

## Execution

```bash
cd examples/15_evaluation_llm_judge
dart pub get
dart run bin/main.dart
```

---

### 한국어
`LocalEvalService` 및 `EvalCase` 데이터셋을 활용하여 에이전트의 다중 턴 추론 궤적(Trajectory), 응답 충실도(Faithfulness) 및 기대 정답 일치도를 정량적으로 평가하고 벤치마킹하는 CI/CD 검증 예제입니다.

### 日本語
`LocalEvalService` および `EvalCase` データセットを活用して、エージェントのマルチターン推論軌跡 (Trajectory)、応答忠実度 (Faithfulness)、期待出力一致度を定量的に評価・ベンチマークする CI/CD 検証サンプルです。

### 中文
利用 `LocalEvalService` 和 `EvalCase` 数据集，对智能体的多轮推理轨迹 (Trajectory)、回复忠实度 (Faithfulness) 及预期结果匹配度进行定量评测与基准测试的 CI/CD 验证示例。
