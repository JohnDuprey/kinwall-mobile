# Check a recipe before adding it

Share a recipe link to Kinwall on iPhone, iPad or Android. On **Check the recipe**, check the
title and recipe details, then choose **Add to Kinwall**.

When Kinwall detects a recipe's type, **Type** starts on **Main dish**, **Side**, **Dessert** or
**Basic**. Tap it to choose another type before adding the recipe. The system picker follows the
phone's light or dark appearance and supports VoiceOver or TalkBack. Type labels are available in
English and German.

The preview's optional `recipe.kind` uses `meal`, `side`, `dessert` or `basic`; `meal` is shown as
Main dish. Changing the picker sends `recipeKind` with the preview token on the save request.
Leaving the choice alone keeps Kinwall's detected type. Other kinds of shares never send a recipe
type.

With an older server that leaves out the detected type, the card has no Type picker and saves as
before, without `recipeKind`. An unrecognized future type also leaves the picker hidden. Servers
that do not support preview cards keep their existing immediate-save behavior.
