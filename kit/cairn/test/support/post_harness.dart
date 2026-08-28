/// Shared harness for kit/cairn behavior tests: a `posts` entity wired
/// through the REAL local-open path (applySchema → subscribeTables →
/// pauseSync) over a [FakeCairnEngine] — no native library involved.
library;

import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

import 'package:arxa_kit_cairn/arxa_kit_cairn_testing.dart';

typedef PostsHarness = ({
  CairnKitRepository<Post> repo,
  FakeCairnEngine engine,
  ArxaKitIdService ids,
});

const postRegistration = ArxaKitEntityRegistration<Post>(
  schema: postSchema,
  fromJson: Post.fromJson,
  toJson: Post.toRow,
);

/// Counter-tier registration: table `counter_posts` carries the counter-flagged
/// `likes` column. The engine merges one CRDT tier per table, so the harness
/// keeps counter and or-set fixtures on separate tables.
const counterPostRegistration = ArxaKitEntityRegistration<Post>(
  schema: counterPostSchema,
  fromJson: counterPostFromJson,
  toJson: counterPostToRow,
);

/// Or-set-tier registration: table `orset_posts` carries the or-set-flagged
/// `tags` column.
const orSetPostRegistration = ArxaKitEntityRegistration<Post>(
  schema: orSetPostSchema,
  fromJson: orSetPostFromJson,
  toJson: orSetPostToRow,
);

Post counterPostFromJson(Map<String, dynamic> json) => Post(
      id: json['id'] as String,
      title: json['title'] as String,
      likes: json['likes'] as int,
      score: 0,
      published: false,
    );

Map<String, dynamic> counterPostToRow(Post p) =>
    {'id': p.id, 'title': p.title, 'likes': p.likes};

Post orSetPostFromJson(Map<String, dynamic> json) => Post(
      id: json['id'] as String,
      title: json['title'] as String,
      likes: 0,
      score: 0,
      published: false,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
    );

Map<String, dynamic> orSetPostToRow(Post p) =>
    {'id': p.id, 'title': p.title, 'tags': p.tags};

/// A minimal posts registration (id + title only, no CRDT flags) — for tests
/// whose behavior doesn't involve the CRDT columns, so the emitted schema and
/// the triple-consistency gate stay out of the way.
const plainPostRegistration = ArxaKitEntityRegistration<Post>(
  schema: ArxaKitTableSchema(
    table: 'posts',
    columns: [
      ArxaKitColumn.id(),
      ArxaKitColumn('title', ArxaKitColumnType.text),
    ],
  ),
  fromJson: plainPostFromJson,
  toJson: plainPostToRow,
);

Post plainPostFromJson(Map<String, dynamic> json) => Post(
      id: json['id'] as String,
      title: json['title'] as String,
      likes: 0,
      score: 0,
      published: false,
    );

Map<String, dynamic> plainPostToRow(Post p) => {'id': p.id, 'title': p.title};

Future<PostsHarness> bootstrapPostsForTest({
  ArxaKitEntityRegistration<Post> registration = postRegistration,
  Set<String> orSetTables = const {},
  Set<String> counterTables = const {},
  String? Function()? userIdProvider,
}) async {
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
    CairnSchemaEmitter().schemaFor([registration.schema]),
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

/// The full posts entity — deliberately plain (no crdt flags): the engine
/// merges one CRDT tier per table, so CRDT fixtures live on the dedicated
/// `counter_posts` / `orset_posts` tables below.
const postSchema = ArxaKitTableSchema(
  table: 'posts',
  columns: [
    ArxaKitColumn.id(),
    ArxaKitColumn('title', ArxaKitColumnType.text),
    ArxaKitColumn('likes', ArxaKitColumnType.integer),
    ArxaKitColumn('score', ArxaKitColumnType.real),
    ArxaKitColumn('published', ArxaKitColumnType.boolean),
    ArxaKitColumn('createdAt', ArxaKitColumnType.timestamptz, nullable: true),
    ArxaKitColumn('tags', ArxaKitColumnType.jsonb, nullable: true),
    ArxaKitColumn('author', ArxaKitColumnType.reference,
        nullable: true, references: 'users'),
    ArxaKitColumn('user_id', ArxaKitColumnType.text, nullable: true),
  ],
);

const counterPostSchema = ArxaKitTableSchema(
  table: 'counter_posts',
  columns: [
    ArxaKitColumn.id(),
    ArxaKitColumn('title', ArxaKitColumnType.text),
    ArxaKitColumn('likes', ArxaKitColumnType.integer,
        crdt: ArxaKitCrdtTier.counter),
  ],
);

const orSetPostSchema = ArxaKitTableSchema(
  table: 'orset_posts',
  columns: [
    ArxaKitColumn.id(),
    ArxaKitColumn('title', ArxaKitColumnType.text),
    ArxaKitColumn('tags', ArxaKitColumnType.jsonb,
        nullable: true, crdt: ArxaKitCrdtTier.orSet),
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
