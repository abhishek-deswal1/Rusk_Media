abstract interface class TipsRepository {
  bool get seen;

  Future<void> markSeen();
}
