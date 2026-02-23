import 'live_request_queue.dart';

class ActiveStreamingTool {
  ActiveStreamingTool({this.task, this.stream});

  Future<Object?>? task;
  LiveRequestQueue? stream;
}
