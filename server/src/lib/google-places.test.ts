import assert from "node:assert/strict";
import { test } from "node:test";
import { normalizePlaceDetails } from "./google-places.js";

test("normalizePlaceDetails maps a Text Search response", () => {
  const details = normalizePlaceDetails({
    places: [
      {
        displayName: { text: "La Mar Cocina Peruana", languageCode: "en" },
        formattedAddress: "PIER 1 1/2 The Embarcadero N, San Francisco, CA 94105, USA",
        rating: 4.6,
        userRatingCount: 3812,
        priceLevel: "PRICE_LEVEL_EXPENSIVE",
        nationalPhoneNumber: "(415) 397-8880",
        websiteUri: "https://lamarcocinaperuana.com/",
        photos: [
          {
            name: "places/ChIJ123/photos/AUacShh3",
            widthPx: 6000,
            heightPx: 4000,
            authorAttributions: [{ displayName: "John Smith", uri: "//maps.google.com/x" }],
          },
          { name: "places/ChIJ123/photos/ZZZ9", authorAttributions: [] },
        ],
        regularOpeningHours: {
          openNow: true,
          weekdayDescriptions: ["Monday: 11:30 AM – 9:30 PM", "Tuesday: 11:30 AM – 9:30 PM"],
        },
      },
    ],
  });

  assert.deepEqual(details, {
    name: "La Mar Cocina Peruana",
    address: "PIER 1 1/2 The Embarcadero N, San Francisco, CA 94105, USA",
    rating: 4.6,
    userRatingCount: 3812,
    openNow: true,
    weekdayHours: ["Monday: 11:30 AM – 9:30 PM", "Tuesday: 11:30 AM – 9:30 PM"],
    priceLevel: "PRICE_LEVEL_EXPENSIVE",
    phone: "(415) 397-8880",
    website: "https://lamarcocinaperuana.com/",
    photos: [
      { name: "places/ChIJ123/photos/AUacShh3", author: "John Smith" },
      { name: "places/ChIJ123/photos/ZZZ9", author: null },
    ],
  });
});

test("normalizePlaceDetails tolerates missing optional fields", () => {
  const details = normalizePlaceDetails({ places: [{ displayName: { text: "Somewhere" } }] });
  assert.deepEqual(details, {
    name: "Somewhere",
    address: null,
    rating: null,
    userRatingCount: null,
    openNow: null,
    weekdayHours: [],
    priceLevel: null,
    phone: null,
    website: null,
    photos: [],
  });
});

test("normalizePlaceDetails caps photos and skips nameless entries", () => {
  const details = normalizePlaceDetails({
    places: [
      {
        displayName: { text: "Somewhere" },
        photos: [
          { name: "places/a/photos/1" },
          { widthPx: 100 },
          { name: "places/a/photos/2" },
          { name: "places/a/photos/3" },
          { name: "places/a/photos/4" },
          { name: "places/a/photos/5" },
          { name: "places/a/photos/6" },
        ],
      },
    ],
  });
  assert.deepEqual(
    details?.photos.map((p) => p.name),
    [
      "places/a/photos/1",
      "places/a/photos/2",
      "places/a/photos/3",
      "places/a/photos/4",
      "places/a/photos/5",
    ],
  );
});

test("normalizePlaceDetails returns null when there is no match", () => {
  assert.equal(normalizePlaceDetails({ places: [] }), null);
  assert.equal(normalizePlaceDetails({}), null);
  assert.equal(normalizePlaceDetails({ error: { code: 400 } }), null);
  assert.equal(normalizePlaceDetails(null), null);
});
