# Illustrated story stages

All five current places (supermarket, office, restaurant, station, home) use independent photographic backgrounds and transparent 2D Moira sprites. Unknown future places retain the existing stage. Artwork is bundled; the reader never downloads or generates an image.

## Presentation contract

`Story.Segment.stage` is optional and has optional string fields `areaId` and `moiraAction`. It is a complete snapshot for that segment, not a transition command. Both streamed segments and the final story use the same normalized cues. Missing, malformed and unknown cues must never invalidate sentence text, translations, readings or word IDs.

Each place has a general interior plus three regions:

| Place | Regions | Prop actions |
| --- | --- | --- |
| supermarket | entrance / produce / checkout | hold_apple / carry_bag |
| office | desk / meeting / breakroom | read_document / use_laptop |
| restaurant | entrance / dining / checkout | read_menu / hold_cup |
| station | concourse / gate / platform | hold_ticket / check_map |
| home | living / kitchen / bedroom | read_book / hold_cup |

All places share greet / listen / think / confused / surprised / point / nod / goodbye. `StoryStagePresentation` owns resolution and checks both fields independently against the selected place. Unknown or unrelated areas resolve to that place's general interior. The opening uses greet; unknown or unrelated actions use listen for the reader, otherwise think. Props describe Moira's actual current actions, never a mentioned object or the person's action. The same cup sprite is shared by restaurant and home.

There are 20 background JPEGs and 17 transparent sprite PNGs, approximately 21.5 MB total. No fixed route is imposed on stories. Unsupported areas remain general (for example dairy/freezer shelves, restaurant kitchens, train interiors, or home bathrooms).

`StorySpriteMetrics` records measured alpha bounds, so different silhouettes share a visible-height scale and ground baseline. Asset names and source-image hashes are in `assets.json`; each entry also records the exact built-in imagegen prompt. Backgrounds are encoded as JPEG for bundling, and sprite PNG alpha is preserved. The source archive is delivered separately with the project artifacts.

## Reading behavior

- One tap completes typing, the next advances. Furigana appears as a complete sentence. New spoken lines play automatically; narration does not. Reading never advances automatically.
- Audio, translation and practice have independent hit targets. Translation persists within the story. Practice opens a sheet without recording; leaving it or the reader cancels recording and playback.
- The dialogue text scrolls within a maximum 45% of stage height after accounting for the measured nameplate and controls. A finite width is required when measuring the ruby layout. Each new segment resets the text scroll position.
- At accessibility sizes, controls become a single row of 44-point icon buttons with full accessibility labels. Artwork scales into the remaining space and reserves clearance below the scene controls. Reduce Motion disables the 200 ms artwork fades.
- Transcript contains only already-shown segments of the current story. It is not a saved-story library.

## Verification

`StoryFormatTests`, `StoryStagePresentationTests` and the backend story tests cover old replies, lossy optional metadata, chunked streaming/final parity, missing words and the existing paid operation. Artwork tests check every declared asset and grounding bounds.

Debug launch: `-StoryStageDemo <sceneId>` has a local story for each of the five places, covering all regions and prop actions without spending points. `-StoryStageLine <number> -StoryStageTranslation` starts at a selected line with translation for visual QA; these options are Debug-only and only act with the demo. `-StoryStageScrollToEnd` is a Debug-only probe for inspecting long text at accessibility sizes; it is absent from Release behavior.

Deploy the additive backend first, then the iOS beta. No route, database migration, pricing formula or request-ID behavior is changed.


The model-only `propEvidence` field quotes the current narration before selecting a prop action. The backend checks that the quote is verbatim, names Moira, and belongs to that narration. Spoken lines may continue only an already established prop; the next narration clears it unless it supplies fresh evidence. The quote is stripped before streaming or returning a segment, preserving the public two-field stage shape. This is a conservative display guard, not natural-language verification. The same stateful resolver processes streamed and final segments in order; spoken suggestions cannot change the established area. Unknown or missing area hints still fall back to general.
