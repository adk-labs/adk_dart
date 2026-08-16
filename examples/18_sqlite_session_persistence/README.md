# 18. SQLite Session Persistence

Demonstrates transactional event logging, session rollback/rewind, and cross-process persistence using `SqliteSessionService`.

## Execution

```bash
cd examples/18_sqlite_session_persistence
dart pub get
dart run bin/main.dart
```

---

### 한국어
`SqliteSessionService`를 활용하여 ACID 트랜잭션이 보장되는 SQLite 디스크 스토리지에 대화 이벤트 스트림을 영속화하고, 프로세스 재시작 시에도 이전 세션 상태와 메모리 컨텍스트를 완벽하게 복원 및 리와인드(Rewind)하는 예제입니다.

### 日本語
`SqliteSessionService` を活用し、ACID トランザクションが保証された SQLite ディスクストレージに対話イベントストリームを永続化し、プロセス再起動後も以前のセッション状態とメモリコンテキストを完全に復元・リワインド (Rewind) するサンプルです。

### 中文
利用 `SqliteSessionService` 在具备 ACID 事务保证的 SQLite 磁盘存储中持久化对话事件流，在进程重启后完整恢复会话状态并支持历史重退 (Rewind) 的示例。
