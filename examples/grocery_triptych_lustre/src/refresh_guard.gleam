pub type Plan {
  ScheduleFlush
  NoSchedule
}

pub fn request(refresh_scheduled: Bool) -> #(Bool, Plan) {
  case refresh_scheduled {
    True -> #(True, NoSchedule)
    False -> #(True, ScheduleFlush)
  }
}

pub fn flush(_refresh_scheduled: Bool) -> Bool {
  False
}
