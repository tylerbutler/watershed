// The flow-dot layer: little dots that travel between a client node and the
// sequencer node to visualise an op moving across the wire. Extracted verbatim
// from the interactive demos (CRDT structures + JSON-OT) so they share one
// implementation.

export interface FlowLayer {
  /**
   * Animate a dot from the centre of `fromEl` to the centre of `toEl` over
   * `duration` ms. `sequenced` selects the post-sequencer styling (the dot
   * carries an assigned sequence number on the return leg). When `label` is
   * given it rides along with the dot to name the op/value in flight.
   */
  animateDot(
    fromEl: Element,
    toEl: Element,
    duration: number,
    sequenced: boolean,
    label?: string,
  ): void;
}

/**
 * Create a flow layer bound to `flowLayer`. Dots are skipped entirely when
 * `reducedMotion()` reports true.
 */
export function createFlowLayer(
  flowLayer: HTMLElement,
  reducedMotion: () => boolean,
): FlowLayer {
  function anchor(el: Element): [number, number] {
    const layerBox = flowLayer.getBoundingClientRect();
    const box = el.getBoundingClientRect();
    return [
      box.left + box.width / 2 - layerBox.left,
      box.top + box.height / 2 - layerBox.top,
    ];
  }

  function animateDot(
    fromEl: Element,
    toEl: Element,
    duration: number,
    sequenced: boolean,
    label?: string,
  ): void {
    if (reducedMotion()) return;
    const dot = document.createElement("span");
    dot.className = sequenced ? "flow-dot sequenced" : "flow-dot";
    if (label) {
      const tag = document.createElement("span");
      tag.className = "flow-dot-label";
      tag.textContent = label;
      dot.append(tag);
    }
    flowLayer.append(dot);
    const [x0, y0] = anchor(fromEl);
    const [x1, y1] = anchor(toEl);
    const anim = dot.animate(
      [
        { transform: `translate(${x0 - 5}px, ${y0 - 5}px)`, opacity: 0.3 },
        { transform: `translate(${x1 - 5}px, ${y1 - 5}px)`, opacity: 1 },
      ],
      { duration: Math.max(180, duration), easing: "ease-in-out" },
    );
    anim.onfinish = () => dot.remove();
  }

  return { animateDot };
}
