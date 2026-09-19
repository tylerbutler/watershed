import assert from "node:assert/strict";
import test from "node:test";
import { startHeroDrift, stopHeroDrift } from "../src/watershed_site/client/home_ffi.mjs";

function contourField() {
  const paths = Array.from({ length: 13 }, (_, index) => ({
    id: `contour-${index}`,
    d: "original",
    setAttribute(name, value) {
      if (name === "d") this.d = value;
    },
  }));
  return {
    paths,
    querySelector(selector) {
      return paths.find((path) => `#${path.id}` === selector);
    },
  };
}

test("uses the supplied SVG and reduced-motion Boolean", () => {
  const reducedField = contourField();
  assert.doesNotThrow(() => startHeroDrift(reducedField, true));
  assert.equal(reducedField.paths.every((path) => path.d !== "original"), true);

  const animatedField = contourField();
  let observed;
  let requestedFrames = 0;
  class IntersectionObserver {
    constructor(callback) {
      this.callback = callback;
    }
    observe(field) {
      observed = field;
      this.callback([{ isIntersecting: true }]);
    }
    disconnect() {}
  }
  animatedField.ownerDocument = {
    defaultView: {
      IntersectionObserver,
      requestAnimationFrame() {
        requestedFrames += 1;
        return requestedFrames;
      },
      cancelAnimationFrame() {},
    },
  };

  assert.doesNotThrow(() => startHeroDrift(animatedField, false));
  assert.equal(observed, animatedField);
  assert.equal(requestedFrames, 1);
  stopHeroDrift(animatedField);
});
