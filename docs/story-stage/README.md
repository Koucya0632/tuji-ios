# Supermarket story stage

The supermarket reader uses independent photographic backgrounds and transparent 2D Moira sprites. Other places retain the existing stage. Artwork is bundled; the reader never downloads or generates an image.

## Presentation contract

`Story.Segment.stage` is optional and has optional string fields `areaId` and `moiraAction`. It is a complete snapshot for that segment, not a transition command. Both streamed segments and the final story use the same normalized cues. Missing, malformed and unknown cues must never invalidate sentence text, translations, readings or word IDs.

Areas: `general`, `entrance`, `produce`, `checkout`. Unknown areas use `general`. Dairy shelves, freezers and stock rooms use the general interior. No fixed route is imposed on a generated story.

Actions: `greet`, `listen`, `think`, `confused`, `surprised`, `point`, `nod`, `goodbye`, `hold_apple`, `carry_bag`. The opening uses `greet`; an unknown action uses `listen` for the reader's line, otherwise `think`. Props describe Moira's actual current actions, never merely a mentioned object or the person's action.

`SupermarketPresentation` owns cue resolution. `StorySpriteMetrics` records measured alpha bounds, so different silhouettes share a visible-height scale and ground baseline. Asset names and source-image hashes are in `assets.json`; each entry also records the exact built-in imagegen prompt. Backgrounds are encoded as JPEG for bundling, and sprite PNG alpha is preserved. The source archive is delivered separately with the project artifacts.

## Reading behavior

- One tap completes typing, the next advances. Furigana appears as a complete sentence. New spoken lines play automatically; narration does not. Reading never advances automatically.
- Audio, translation and practice have independent hit targets. Translation persists within the story. Practice opens a sheet without recording; leaving it or the reader cancels recording and playback.
- The dialogue text scrolls within a maximum 45% of stage height after accounting for the measured nameplate and controls. A finite width is required when measuring the ruby layout. Each new segment resets the text scroll position.
- At accessibility sizes, controls become a single row of 44-point icon buttons with full accessibility labels. Artwork scales into the remaining space and reserves clearance below the scene controls. Reduce Motion disables the 200 ms artwork fades.
- Transcript contains only already-shown segments of the current story. It is not a saved-story library.

## Verification

`StoryFormatTests`, `StoryStagePresentationTests` and the backend story tests cover old replies, lossy optional metadata, chunked streaming/final parity, missing words and the existing paid operation. Artwork tests check every declared asset and grounding bounds.

Debug launch: `-StoryStageDemo supermarket` exercises an apple-shopping story, prop actions and a checkout transition without spending points. Other scene IDs exercise the original stage. `-StoryStageScrollToEnd` is a Debug-only probe for inspecting long text at accessibility sizes; it is absent from Release behavior.

Deploy the additive backend first, then the iOS beta. No route, database migration, pricing formula or request-ID behavior is changed.
