// bundled sample reels until the catalogue api is live; it answers in the
// same shape the endpoint will, so swapping it out only touches this file
class ReelsSeedSource {
  const ReelsSeedSource();

  static const String _base =
      'https://res.cloudinary.com/dgnl7i05i/video/upload';

  // episode 8 is placeholder content reusing episode 1, so the lock after
  // episode 7 has something to hold back
  static const List<String> _clips = [
    'ep1_t6cacq',
    'ep2_axq5qd',
    'ep3_ubccti',
    'ep4_bb7wfr',
    'ep5_qb5gkf',
    'ep6_paoxly',
    'ep7_xqkcjq',
    'ep1_t6cacq',
  ];

  static final List<Map<String, dynamic>> _catalogue = [
    for (var i = 0; i < _clips.length; i++)
      {
        'reel_id': 'ep${i + 1}',
        'caption': 'Episode ${i + 1}',
        'stream': '$_base/${_clips[i]}.mp4',
        'poster': '$_base/so_0,w_720,h_1280,c_fill,q_auto/${_clips[i]}.jpg',
        'creator': {
          'handle': 'ruskmedia.drama',
          'avatar': 'https://i.pravatar.cc/150?img=21',
        },
        'stats': {
          'likes': 1820 + i * 640,
          'comments': 142 + i * 37,
          'shares': 96 + i * 21,
        },
      },
  ];

  Future<Map<String, dynamic>> page({
    required int cursor,
    required int count,
  }) async {
    final from = cursor.clamp(0, _catalogue.length);
    final to = (from + count).clamp(from, _catalogue.length);
    return {
      'data': _catalogue.sublist(from, to),
      'more': to < _catalogue.length,
    };
  }
}
