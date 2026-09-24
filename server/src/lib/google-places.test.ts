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
  });
});

test("normalizePlaceDetails returns null when there is no match", () => {
  assert.equal(normalizePlaceDetails({ places: [] }), null);
  assert.equal(normalizePlaceDetails({}), null);
  assert.equal(normalizePlaceDetails({ error: { code: 400 } }), null);
  assert.equal(normalizePlaceDetails(null), null);
});
