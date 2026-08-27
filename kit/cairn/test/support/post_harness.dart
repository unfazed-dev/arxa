/// Shared harness for kit/cairn behavior tests: a `posts` entity wired
/// through the REAL local-open path (applySchema → subscribeTables →
/// pauseSync) over a [FakeCairnEngine] — no native library involved.
library;

import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

import 'fake_cairn_engine.dart';

typedef PostsHarness = ({
  CairnKitRepository<Post> repo,
  FakeCairnEngine engine,
  ArxaKitIdService ids,
});

Future<PostsHarness> bootstrapPostsForTest({
  Set<String> orSetTables = const {},
  Set<String> counterTables = const {},
  String? Function()? userIdProvider,
}) async {
  const registration = ArxaKitEntityRegistration<Post>(
    schema: postSchema,
    fromJson: Post.fromJson,
    toJson: Post.toRow,
  );
  final engine = FakeCairnEngine();
  // Test seams from cairn_flutter — the pure-Dart path engine.dart documents.
  // ignore: invalid_use_of_visible_for_testing_member
  final cairn = Cairn.withEngine(
    engine,
    orSetTables: orSetTables,
    counterTables: counterTables,
  );
  // ignore: invalid_use_of_visible_for_testing_member
  final db = await CairnDatabase.localForTest(
    cairn,
    CairnSchemaEmitter().schemaFor(const [postSchema]),
  );
  final ids = ArxaKitIdService();
  return (
    repo: CairnKitRepository<Post>(
      db: db,
      registration: registration,
      idService: ids,
      orSetTables: orSetTables,
      counterTables: counterTables,
      userIdProvider: userIdProvider,
    ),
    engine: engine,
    ids: ids,
  );
}

const postSchema = ArxaKitTableSchema(
  table: 'posts',
  columns: [
    ArxaKitColumn.id(),
    ArxaKitColumn('title', ArxaKitColumnType.text),
    ArxaKitColumn('likes', ArxaKitColumnType.integer,
        crdt: ArxaKitCrdtTier.counter),
    ArxaKitColumn('score', ArxaKitColumnType.real),
    ArxaKitColumn('published', ArxaKitColumnType.boolean),
    ArxaKitColumn('createdAt', ArxaKitColumnType.timestamptz, nullable: true),
    ArxaKitColumn('tags', ArxaKitColumnType.jsonb,
        nullable: true, crdt: ArxaKitCrdtTier.orSet),
    ArxaKitColumn('author', ArxaKitColumnType.reference,
        nullable: true, references: 'users'),
    ArxaKitColumn('user_id', ArxaKitColumnType.text, nullable: true),
  ],
);

class Post {
  const Post({
    required this.id,
    required this.title,
    required this.likes,
    required this.score,
    required this.published,
    this.createdAt,
    this.tags,
    this.author,
    this.userId,
  });

  final String id;
  final String title;
  final int likes;
  final double score;
  final bool published;
  final String? createdAt;
  final List<String>? tags;
  final String? author;
  final String? userId;

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as String,
        title: json['title'] as String,
        likes: json['likes'] as int,
        score: json['score'] as double,
        published: json['published'] as bool,
        createdAt: json['createdAt'] as String?,
        tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
        author: json['author'] as String?,
        userId: json['user_id'] as String?,
      );

  static Map<String, dynamic> toRow(Post p) => {
        'id': p.id,
        'title': p.title,
        'likes': p.likes,
        'score': p.score,
        'published': p.published,
        'createdAt': p.createdAt,
        'tags': p.tags,
        'author': p.author,
        'user_id': p.userId,
      };

  Post copyWith({String? title, int? likes, String? userId}) => Post(
        id: id,
        title: title ?? this.title,
        likes: likes ?? this.likes,
        score: score,
        published: published,
        createdAt: createdAt,
        tags: tags,
        author: author,
        userId: userId ?? this.userId,
      );

  @override
  bool operator ==(Object other) =>
      other is Post &&
      id == other.id &&
      title == other.title &&
      likes == other.likes &&
      score == other.score &&
      published == other.published &&
      createdAt == other.createdAt &&
      listEquals(tags, other.tags) &&
      author == other.author &&
      userId == other.userId;

  @override
  int get hashCode => Object.hash(id, title, likes, score, published);

  @override
  String toString() => 'Post($id, $title, likes: $likes)';
}

bool listEquals(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
