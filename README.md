# Rusk Media — micro-drama reels player

A vertical short-video feed for episodic drama, built in Flutter for Android. Eight
episodes, an ad after every third one, a paywall on episode 7, first-run tips and a
little hand that shows you the gestures. The interesting part is not the UI, it is
keeping three video decoders alive while you flick through a feed without the app
falling over.

This file is about how the thing is actually built and why. If you only want to run
it, the next section is enough.

## Running it

The project is pinned to Flutter 3.24.4 / Dart 3.5.4 through FVM (`.fvmrc`). A newer
global Flutter will resolve packages the IDE then can't use, so always go through the
FVM binary:

```sh
fvm flutter pub get
fvm flutter run                      # debug on the connected device
fvm flutter test                     # whole suite, ~6s
fvm dart analyze lib test
fvm flutter build apk --debug
```

If you don't have FVM: `~/fvm/versions/3.24.4/bin/flutter` works the same way.

Portrait only, Android first. There is no backend; the catalogue is seeded from
Cloudinary URLs in `reels_seed_source.dart`. Ads load from Google's sample Ad Manager
units, so you will see the "Ad Manager native ad validator" bubble on debug builds.
That is Google's debug overlay, not ours.

## What it does

- **Feed.** E1 E2 E3 AD E4 E5 E6 AD E7 E8. Swipe up for the next one. The focused reel
  plays, the neighbours sit ready, the two after that are quietly fetched to disk.
- **Gestures.** Tap pauses. Double-tap likes (heart burst at the finger). Hold and slide
  up/down for volume, hold and slide sideways to scrub. The bottom line is also a seek
  bar. On Android the volume gesture moves the phone's own media volume, the same level
  the hardware keys change, and the meter follows the keys too. The sound button is a
  mute for the app only; it never touches the phone's level.
- **Ads.** Native ads from GAM test units, requested three pages ahead, shown as "a
  short break" in the story: Google's template inside an outlined card, with a swipe
  hint underneath. A slot that
  errors, comes back empty or takes more than 8s leaves the feed, and it leaves without
  anything on screen jumping.
- **Paywall.** Episode 7 is locked. You can see its poster behind a blur, you can't
  scroll past it, and "Unlock Episode" opens the rest for this session. There is no
  real purchase yet, see "Placeholders".
- **First run.** A tips sheet on the first launch, then a three-step guide (volume,
  timeline, swipe) acted out by a hand. Both are stored so they show once.
- **Offline.** Loading, no-internet, error and empty states share one view. Retry polls
  every 3s while offline and recovers by itself.

## How it is put together

```
lib/
  main.dart                    boot order, edge-to-edge posture (set once, here only)
  core/
    base/                      BaseBloc / BaseEvent / BaseState, BaseMultiBlocProviderWidget
    di/                        AppDI (app lifetime), ReelsDI (one set per screen visit)
    video_pool/                VideoPoolBloc: the only thing that owns a video controller
    ads/                       AdPreloader, AdConfig (test units), per-slot ad state
    lifecycle/                 app background/foreground → pool, single owner
    communication/             RepositoryResponse / UseCaseResponse
    ui/components/             CustomText, LocalImageWidget, NetworkImageWidget
    theme/, constants/, logger/, network/
  features/
    launch/                    the intro animation
    reels/
      data/                    seed source, DTO parsing, repository impls
      domain/                  entities, repository interfaces, use cases, policies
      presentation/            four blocs, ReelsScreen, the widgets
  shared/widgets/connection_state/   loading / offline / error / empty view
test/                          mirrors lib/
```

Layers are the usual ones. `domain/` is plain Dart and knows nothing about Flutter.
`data/` turns JSON into entities and never lets a bad field crash the feed. Presentation
talks to blocs, blocs talk to use cases. Concrete classes are built only in `core/di/`.

Errors are values, not exceptions: a data source returns a `RepositoryResponse`, a use
case returns a `UseCaseResponse`, and the bloc switches over the cases. Nothing throws
across a layer.

### The video pool

`VideoPoolBloc` lives for the whole app (`AppDI.videoPool`) and is the single owner of
every `VideoPlayerController`. Screens tell it which pages should be live
(`VideoPoolWindowChanged`) and whether playback is held (`VideoPoolHoldChanged`); it
decides what to create, what to pause and what to dispose.

Things it does that are easy to miss:

- Every load carries a token. A result whose token no longer matches (the page left, or
  was re-requested) is disposed on arrival, never applied.
- Stale controllers are disposed a frame late, because the widgets still hold them until
  the next build.
- A player that dies *after* it was ready (stream drops, corrupt cache file) is caught by
  a value listener and marked failed, so the reel shows its retry card instead of a
  black frame.
- `pause()` is never gated on `isPlaying`. ExoPlayer reports "not playing" while it
  waits on audio focus or a buffer, and then resumes on its own. If we trusted that flag
  a reel could keep playing in the background after a phone call.
- At most two players initialise at once. The focused page never waits; neighbours
  queue with the reel ahead first. An initialise can't be called off once it starts, so
  the saving comes from never starting the ones a fast flick has already left behind,
  and from a page that leaves the window giving its turn up straight away.
- `CachedVideoControllerFactory` plays from disk when the file is there, otherwise
  streams and downloads a copy once the stream is up, so the first frame never waits on
  a full download. Warm clips download one at a time and each new window replaces the
  ones still waiting; the cache manager has no cancel, so that is how a flick avoids
  fetching clips nobody will reach.

Budget: the focused reel and one either side are live (three decoders), the next two are
disk-only. Those two numbers sit at the top of `ReelsScreen` and are the only knob.

### The reels screen and its four blocs

One screen, four blocs, none of which imports another:

| Bloc | Owns |
|---|---|
| `ReelsBloc` | the feed: loading, paging, offline/retry, focused page, ad-slot removal |
| `EngagementBloc` | likes and follows for this visit |
| `PaywallBloc` | one bool, `unlocked`; the lock position is derived from feed data |
| `OnboardingBloc` | tips pending, gesture guide armed |

Anything that needs two of them is worked out in `ReelsScreen` as a small static
function with its own tests: `holdsPlayback` (tips, paywall or an ad on screen → hold
the pool), `poolWindow` (which episodes get a player, what to prefetch, where the lock
cuts it off), `movedToAnotherReel` (disarms the guide), `canFocus` (nothing past the
lock). The screen listens to the blocs and feeds those results to the pool.

The feed itself is never stored. `ReelsState.items` is composed on read from the loaded
reels minus the removed ad slots (`FeedComposer`), so paging and slot removal can't
disagree about what page 7 is. Players are keyed by the episode's catalogue index, not
the page, which is why dropping an ad slot above you doesn't reload a video.

### Ads

`AdPreloader` owns the `NativeAd` objects and their lifetimes; the feed only sees slot
ids and a failures stream. When a slot fails, `FeedComposer.planRemoval` decides how it
leaves: a slot ahead just goes, a slot behind goes with a same-frame page correction so
nothing visibly moves, and a slot you are looking at glides you off first. Removal only
runs while the feed is at rest, never under a finger.

### Paywall

`EpisodePaywall` is a pure policy (which index is locked, which page that is in the
composed feed). `PaywallLockPhysics` stops the scroll at that page with a damped stretch
and reads the locked page from a `ValueNotifier` rather than a constructor argument,
because `Scrollable` keeps the first physics it was given and the locked page moves
when an ad before it is dropped. The locked episode is fetched to disk but never gets a
player, so unlocking plays instantly; nothing past it is fetched at all. The paywall
layer stays mounted on that page while it scrolls, so swiping away plays the leave
(blur and card ease out) instead of cutting off at the half-page point.

### Phone volume

`SystemVolumeService` talks to `MainActivity` over a `system_volume` channel: read and set
the media stream, plus a stream of changes from the hardware keys. The pool only switches
to it once the first read answers, so iOS, tests and fixed-volume devices keep the app's
own volume. A set replies with the level the phone actually took (it has its own 15-ish
steps, and Do Not Disturb can refuse), and that is what the meter starts from next time.

### Edge-to-edge

`main.dart` sets `SystemUiMode.edgeToEdge` and the overlay style once, for the whole
app. No screen or shared view re-declares it. Video runs under the bars; every button,
the ad container, the paywall card, the tips sheet and the guide hand sit inside a
`SafeArea`.

## Decisions worth knowing about

- **App-lifetime pool, screen-scoped everything else.** Controllers are expensive and
  pausing on background needs exactly one owner. Likes, unlock and tips are
  cheap and belong to one visit of the screen, so `ReelsDI` builds fresh blocs each
  time.
- **Four blocs instead of one.** The first version had everything in `ReelsBloc`. It
  worked, but every change touched the same 400-line file and every test needed the
  whole state. Splitting by concern made the glue explicit, and the glue turned out to
  be four tiny functions we could test on their own.
- **Pure policies for the parts that are easy to get wrong.** `FeedComposer`,
  `EpisodePaywall`, `poolWindow`: no widgets, no mocks, just inputs and outputs. These
  have caught more regressions than any widget test.
- **No retry/cancel in the data layer yet.** The seed source can't fail in interesting
  ways. When a real backend lands, retries belong in the repository, not the bloc.
- **The paywall blur is a live `BackdropFilter`.** It is re-rasterised on every frame
  the card animates. We know. It only runs on the locked episode over a still poster,
  and a pre-blurred image would not blur the rail and top bar the same way. Measure on
  a real device before changing it.

## Placeholders

Things that are deliberately not real yet:

- **Content.** Eight Cloudinary clips; episode 8 reuses episode 1 so the lock has
  something to hold back.
- **Ad units.** Google's sample Ad Manager units and the sample app id in the manifest.
  Never a production unit in this repo.
- **Purchase.** The brief asks for a simulated unlock, so "Unlock Episode" at ₹49 is a
  600ms timer. When a real purchase comes in,
  its result must land in `PaywallBloc`, not in the widget, so a swipe mid-purchase
  can't lose it.
- **Release config.** `applicationId` is still `com.example.rusk_media` and `targetSdk`
  follows Flutter's default (34). Release builds sign with the key named in
  `android/key.properties` (not in git); without that file they fall back to the debug
  key.
  All three change together before anything ships.

## Testing

```sh
fvm flutter test                          # everything
fvm flutter test test/features/reels/     # one area
```

210 tests at the time of writing. The habit: a bug fix ships with a test that fails on
the old code, and we actually run it against the old code first. Pure policies and
blocs are unit tested; widgets are tested where the test is cheap and guards something
real (rebuild scope, gesture arena, the paywall never mounting a player).

`test/helpers/fake_video_controller.dart` stands in for the plugin. It counts pauses
and can `fail()` or `suppress()` itself, which is how the pool's error and audio-focus
paths are tested without a device.

## Known rough edges

- A download or player initialise that has already started runs to the end even if the
  viewer has moved on; it is thrown away when it lands. Only what hasn't started yet is
  dropped.
- The progress bar steps at the plugin's position poll rate rather than interpolating.
- `lib/core/base/base_widget.dart` has no subclass right now; it is the single-bloc
  counterpart of the multi-bloc base and will be used by the next plain screen.
