import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/item_mutation_repository.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/preference/seerr_preferences.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Seerr server whose answer for the title can be changed between refreshes.
class _FakeSeerr extends Fake implements SeerrRepository {
  SeerrMediaInfo mediaInfo = const SeerrMediaInfo(status: 3);

  SeerrMovieDetails get _details => SeerrMovieDetails(
    id: 299534,
    title: 'Avengers: Endgame',
    mediaInfo: mediaInfo,
  );

  @override
  Future<void> ensureInitialized({bool force = false}) async {}

  @override
  Future<Map<String, dynamic>> getPublicSettings() async => const {};

  @override
  Future<SeerrUser> getCurrentUser() async => SeerrUser(id: 1);

  @override
  Future<(SeerrMovieDetails, bool)> getMovieDetailsWithWatchlist(
    int tmdbId,
  ) async => (_details, false);

  @override
  Future<SeerrMovieDetails> getMovieDetails(int tmdbId) async => _details;

  SeerrTvDetails get _tv => SeerrTvDetails(
    id: 1399,
    name: 'A Series',
    numberOfSeasons: 2,
    mediaInfo: mediaInfo,
  );

  @override
  Future<(SeerrTvDetails, bool)> getTvDetailsWithWatchlist(int tmdbId) async =>
      (_tv, false);

  @override
  Future<SeerrTvDetails> getTvDetails(int tmdbId) async => _tv;
}

class _FakePrefs extends Fake implements SeerrPreferences {}

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

/// Answers for the ids in [ids] and 404s for anything else, like a server
/// that dropped an item Seerr still points at.
void _serverHas(_ItemsApi items, Set<String> ids) {
  when(
    () => items.getItem(
      any(),
      mediaSourceId: any(named: 'mediaSourceId'),
      fields: any(named: 'fields'),
    ),
  ).thenAnswer((inv) async {
    final id = inv.positionalArguments.first as String;
    if (ids.contains(id)) return {'Id': id};
    throw Exception('Server returned HTTP 404');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSeerr seerr;
  late _Client client;
  late _ItemsApi items;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    seerr = _FakeSeerr();
    // Registered the way the app does, since the view model reaches it with
    // getAsync.
    GetIt.instance.registerLazySingletonAsync<SeerrRepository>(
      () async => seerr,
    );
    GetIt.instance.registerSingleton<SeerrPreferences>(_FakePrefs());
    client = _Client();
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    items = _ItemsApi();
    when(() => client.itemsApi).thenReturn(items);
    _serverHas(items, {'library-item', '12345'});
  });

  tearDown(() => GetIt.instance.reset());

  test('a title that lands while its page is open swaps it out', () {
    fakeAsync((async) {
      final tmdb = TmdbRepository(client);
      final vm = ItemDetailViewModel(
        itemId: 'tmdb:movie:299534',
        client: client,
        mutations: ItemMutationRepository(client),
        mdbListRepository: MdbListRepository(client, tmdb),
        tmdbRepository: tmdb,
      );
      vm.load();
      async.flushMicrotasks();
      expect(vm.isSeerrOnly, isTrue);
      expect(vm.seerrResolvedLibraryId, isNull);

      seerr.mediaInfo = const SeerrMediaInfo(
        status: 5,
        jellyfinMediaId: 'library-item',
      );
      async.elapse(const Duration(seconds: 30));
      expect(vm.seerrResolvedLibraryId, 'library-item');

      vm.dispose();
    });
  });

  test('on Plex, Seerr\'s ratingKey opens the library copy', () {
    fakeAsync((async) {
      when(() => client.serverType).thenReturn(ServerType.plex);
      seerr.mediaInfo = const SeerrMediaInfo(status: 5, ratingKey: '12345');
      final tmdb = TmdbRepository(client);
      final vm = ItemDetailViewModel(
        itemId: 'tmdb:movie:299534',
        client: client,
        mutations: ItemMutationRepository(client),
        mdbListRepository: MdbListRepository(client, tmdb),
        tmdbRepository: tmdb,
      );
      vm.load();
      async.flushMicrotasks();
      expect(vm.seerrResolvedLibraryId, '12345');
      vm.dispose();
    });
  });

  test('a library id the server no longer has keeps the Seerr page', () {
    fakeAsync((async) {
      when(() => client.serverType).thenReturn(ServerType.plex);
      seerr.mediaInfo = const SeerrMediaInfo(status: 3, ratingKey: 'gone');
      final tmdb = TmdbRepository(client);
      final vm = ItemDetailViewModel(
        itemId: 'tmdb:movie:299534',
        client: client,
        mutations: ItemMutationRepository(client),
        mdbListRepository: MdbListRepository(client, tmdb),
        tmdbRepository: tmdb,
      );
      vm.load();
      async.flushMicrotasks();
      expect(vm.seerrResolvedLibraryId, isNull);
      expect(vm.isSeerrOnly, isTrue);
      expect(vm.item, isNotNull);

      // A refresh asks again only once Seerr points at a different id.
      async.elapse(const Duration(seconds: 30));
      expect(vm.seerrResolvedLibraryId, isNull);
      verify(
        () => items.getItem(
          'gone',
          mediaSourceId: any(named: 'mediaSourceId'),
          fields: any(named: 'fields'),
        ),
      ).called(1);
      vm.dispose();
    });
  });

  test('a series whose library id is stale shows its Seerr page', () {
    fakeAsync((async) {
      when(() => client.serverType).thenReturn(ServerType.plex);
      seerr.mediaInfo = const SeerrMediaInfo(status: 4, ratingKey: 'gone');
      final tmdb = TmdbRepository(client);
      final vm = ItemDetailViewModel(
        itemId: 'tmdb:tv:1399',
        client: client,
        mutations: ItemMutationRepository(client),
        mdbListRepository: MdbListRepository(client, tmdb),
        tmdbRepository: tmdb,
      );
      vm.load();
      async.flushMicrotasks();
      expect(vm.seerrResolvedLibraryId, isNull);
      expect(vm.error, isNull);
      expect(vm.state, ItemDetailState.ready);
      vm.dispose();
    });
  });
}
