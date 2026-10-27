/* parts/PART_NAME.js — one reusable piece, rendered in light DOM so tokens cascade and
 * QA can select its children. Variants come from attributes; no shadow DOM, no fetch. */
customElements.define('mk-PART_NAME', class extends HTMLElement {
  connectedCallback() {
    const active = this.getAttribute('active') || '';
    this.innerHTML = `
      <div class="PART_NAME" data-dsqa-part="PART_NAME">
        <!-- markup, using ${active} etc. Styles live in ../mockup.css under .PART_NAME -->
      </div>`;
  }
});
