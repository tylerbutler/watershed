import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $vattr from "../lustre/vdom/vattr.d.mts";

export type Attribute = $vattr.Attribute$<any>;

export function attribute(name: string, value: string): $vattr.Attribute$<any>;

export function property(name: string, value: $json.Json$): $vattr.Attribute$<
  any
>;

export function class$(name: string): $vattr.Attribute$<any>;

export function none(): $vattr.Attribute$<any>;

export function accesskey(key: string): $vattr.Attribute$<any>;

export function autocapitalize(value: string): $vattr.Attribute$<any>;

export function autocorrect(enabled: boolean): $vattr.Attribute$<any>;

export function autofocus(should_autofocus: boolean): $vattr.Attribute$<any>;

export function classes(names: _.List<[string, boolean]>): $vattr.Attribute$<
  any
>;

export function closedby(value: string): $vattr.Attribute$<any>;

export function command(value: string): $vattr.Attribute$<any>;

export function commandfor(value: string): $vattr.Attribute$<any>;

export function contenteditable(is_editable: string): $vattr.Attribute$<any>;

export function data(key: string, value: string): $vattr.Attribute$<any>;

export function dir(direction: string): $vattr.Attribute$<any>;

export function draggable(is_draggable: boolean): $vattr.Attribute$<any>;

export function enterkeyhint(value: string): $vattr.Attribute$<any>;

export function hidden(is_hidden: boolean): $vattr.Attribute$<any>;

export function id(value: string): $vattr.Attribute$<any>;

export function inert(is_inert: boolean): $vattr.Attribute$<any>;

export function inputmode(value: string): $vattr.Attribute$<any>;

export function is(value: string): $vattr.Attribute$<any>;

export function itemid(id: string): $vattr.Attribute$<any>;

export function itemprop(name: string): $vattr.Attribute$<any>;

export function itemscope(has_scope: boolean): $vattr.Attribute$<any>;

export function itemtype(url: string): $vattr.Attribute$<any>;

export function lang(language: string): $vattr.Attribute$<any>;

export function nonce(value: string): $vattr.Attribute$<any>;

export function popover(value: string): $vattr.Attribute$<any>;

export function spellcheck(should_check: boolean): $vattr.Attribute$<any>;

export function style(property: string, value: string): $vattr.Attribute$<any>;

export function styles(properties: _.List<[string, string]>): $vattr.Attribute$<
  any
>;

export function tabindex(index: number): $vattr.Attribute$<any>;

export function title(text: string): $vattr.Attribute$<any>;

export function translate(should_translate: boolean): $vattr.Attribute$<any>;

export function writingsuggestions(enabled: boolean): $vattr.Attribute$<any>;

export function open(is_open: boolean): $vattr.Attribute$<any>;

export function href(url: string): $vattr.Attribute$<any>;

export function target(value: string): $vattr.Attribute$<any>;

export function download(filename: string): $vattr.Attribute$<any>;

export function ping(urls: _.List<string>): $vattr.Attribute$<any>;

export function rel(value: string): $vattr.Attribute$<any>;

export function hreflang(language: string): $vattr.Attribute$<any>;

export function referrerpolicy(value: string): $vattr.Attribute$<any>;

export function as_(value: string): $vattr.Attribute$<any>;

export function blocking(value: boolean): $vattr.Attribute$<any>;

export function integrity(hash: string): $vattr.Attribute$<any>;

export function alt(text: string): $vattr.Attribute$<any>;

export function src(url: string): $vattr.Attribute$<any>;

export function srcset(sources: string): $vattr.Attribute$<any>;

export function sizes(value: string): $vattr.Attribute$<any>;

export function crossorigin(value: string): $vattr.Attribute$<any>;

export function usemap(value: string): $vattr.Attribute$<any>;

export function ismap(is_map: boolean): $vattr.Attribute$<any>;

export function width(value: number): $vattr.Attribute$<any>;

export function height(value: number): $vattr.Attribute$<any>;

export function decoding(value: string): $vattr.Attribute$<any>;

export function loading(value: string): $vattr.Attribute$<any>;

export function fetchpriority(value: string): $vattr.Attribute$<any>;

export function accept_charset(charsets: string): $vattr.Attribute$<any>;

export function action(url: string): $vattr.Attribute$<any>;

export function enctype(encoding_type: string): $vattr.Attribute$<any>;

export function method(http_method: string): $vattr.Attribute$<any>;

export function novalidate(disable_validation: boolean): $vattr.Attribute$<any>;

export function accept(values: _.List<string>): $vattr.Attribute$<any>;

export function alpha(allowed: boolean): $vattr.Attribute$<any>;

export function autocomplete(value: string): $vattr.Attribute$<any>;

export function checked(is_checked: boolean): $vattr.Attribute$<any>;

export function default_checked(is_checked: boolean): $vattr.Attribute$<any>;

export function colorspace(value: string): $vattr.Attribute$<any>;

export function cols(value: number): $vattr.Attribute$<any>;

export function dirname(direction: string): $vattr.Attribute$<any>;

export function disabled(is_disabled: boolean): $vattr.Attribute$<any>;

export function for$(id: string): $vattr.Attribute$<any>;

export function form(id: string): $vattr.Attribute$<any>;

export function formaction(url: string): $vattr.Attribute$<any>;

export function formenctype(encoding_type: string): $vattr.Attribute$<any>;

export function formmethod(method: string): $vattr.Attribute$<any>;

export function formnovalidate(no_validate: boolean): $vattr.Attribute$<any>;

export function formtarget(target: string): $vattr.Attribute$<any>;

export function list(id: string): $vattr.Attribute$<any>;

export function max(value: string): $vattr.Attribute$<any>;

export function maxlength(length: number): $vattr.Attribute$<any>;

export function min(value: string): $vattr.Attribute$<any>;

export function minlength(length: number): $vattr.Attribute$<any>;

export function multiple(allow_multiple: boolean): $vattr.Attribute$<any>;

export function name(element_name: string): $vattr.Attribute$<any>;

export function pattern(regex: string): $vattr.Attribute$<any>;

export function placeholder(text: string): $vattr.Attribute$<any>;

export function popovertarget(id: string): $vattr.Attribute$<any>;

export function popovertargetaction(action: string): $vattr.Attribute$<any>;

export function readonly(is_readonly: boolean): $vattr.Attribute$<any>;

export function required(is_required: boolean): $vattr.Attribute$<any>;

export function rows(value: number): $vattr.Attribute$<any>;

export function selected(is_selected: boolean): $vattr.Attribute$<any>;

export function default_selected(is_selected: boolean): $vattr.Attribute$<any>;

export function size(value: string): $vattr.Attribute$<any>;

export function step(value: string): $vattr.Attribute$<any>;

export function type_(control_type: string): $vattr.Attribute$<any>;

export function value(control_value: string): $vattr.Attribute$<any>;

export function default_value(control_value: string): $vattr.Attribute$<any>;

export function http_equiv(value: string): $vattr.Attribute$<any>;

export function content(value: string): $vattr.Attribute$<any>;

export function charset(value: string): $vattr.Attribute$<any>;

export function media(query: string): $vattr.Attribute$<any>;

export function autoplay(auto_play: boolean): $vattr.Attribute$<any>;

export function controls(show_controls: boolean): $vattr.Attribute$<any>;

export function loop(should_loop: boolean): $vattr.Attribute$<any>;

export function muted(is_muted: boolean): $vattr.Attribute$<any>;

export function playsinline(play_inline: boolean): $vattr.Attribute$<any>;

export function poster(url: string): $vattr.Attribute$<any>;

export function preload(value: string): $vattr.Attribute$<any>;

export function shadowrootmode(mode: string): $vattr.Attribute$<any>;

export function shadowrootdelegatesfocus(delegates: boolean): $vattr.Attribute$<
  any
>;

export function shadowrootclonable(clonable: boolean): $vattr.Attribute$<any>;

export function shadowrootserializable(serializable: boolean): $vattr.Attribute$<
  any
>;

export function abbr(value: string): $vattr.Attribute$<any>;

export function colspan(value: number): $vattr.Attribute$<any>;

export function headers(ids: _.List<string>): $vattr.Attribute$<any>;

export function rowspan(value: number): $vattr.Attribute$<any>;

export function span(value: number): $vattr.Attribute$<any>;

export function scope(value: string): $vattr.Attribute$<any>;

export function datetime(value: string): $vattr.Attribute$<any>;

export function aria(name: string, value: string): $vattr.Attribute$<any>;

export function role(name: string): $vattr.Attribute$<any>;

export function aria_activedescendant(id: string): $vattr.Attribute$<any>;

export function aria_atomic(value: boolean): $vattr.Attribute$<any>;

export function aria_autocomplete(value: string): $vattr.Attribute$<any>;

export function aria_braillelabel(value: string): $vattr.Attribute$<any>;

export function aria_brailleroledescription(value: string): $vattr.Attribute$<
  any
>;

export function aria_busy(value: boolean): $vattr.Attribute$<any>;

export function aria_checked(value: string): $vattr.Attribute$<any>;

export function aria_colcount(value: number): $vattr.Attribute$<any>;

export function aria_colindex(value: number): $vattr.Attribute$<any>;

export function aria_colindextext(value: string): $vattr.Attribute$<any>;

export function aria_colspan(value: number): $vattr.Attribute$<any>;

export function aria_controls(value: string): $vattr.Attribute$<any>;

export function aria_current(value: string): $vattr.Attribute$<any>;

export function aria_describedby(value: string): $vattr.Attribute$<any>;

export function aria_description(value: string): $vattr.Attribute$<any>;

export function aria_details(value: string): $vattr.Attribute$<any>;

export function aria_disabled(value: boolean): $vattr.Attribute$<any>;

export function aria_errormessage(value: string): $vattr.Attribute$<any>;

export function aria_expanded(value: boolean): $vattr.Attribute$<any>;

export function aria_flowto(value: string): $vattr.Attribute$<any>;

export function aria_haspopup(value: string): $vattr.Attribute$<any>;

export function aria_hidden(value: boolean): $vattr.Attribute$<any>;

export function aria_invalid(value: string): $vattr.Attribute$<any>;

export function aria_keyshortcuts(value: string): $vattr.Attribute$<any>;

export function aria_label(value: string): $vattr.Attribute$<any>;

export function aria_labelledby(value: string): $vattr.Attribute$<any>;

export function aria_level(value: number): $vattr.Attribute$<any>;

export function aria_live(value: string): $vattr.Attribute$<any>;

export function aria_modal(value: boolean): $vattr.Attribute$<any>;

export function aria_multiline(value: boolean): $vattr.Attribute$<any>;

export function aria_multiselectable(value: boolean): $vattr.Attribute$<any>;

export function aria_orientation(value: string): $vattr.Attribute$<any>;

export function aria_owns(value: string): $vattr.Attribute$<any>;

export function aria_placeholder(value: string): $vattr.Attribute$<any>;

export function aria_posinset(value: number): $vattr.Attribute$<any>;

export function aria_pressed(value: string): $vattr.Attribute$<any>;

export function aria_readonly(value: boolean): $vattr.Attribute$<any>;

export function aria_relevant(value: string): $vattr.Attribute$<any>;

export function aria_required(value: boolean): $vattr.Attribute$<any>;

export function aria_roledescription(value: string): $vattr.Attribute$<any>;

export function aria_rowcount(value: number): $vattr.Attribute$<any>;

export function aria_rowindex(value: number): $vattr.Attribute$<any>;

export function aria_rowindextext(value: string): $vattr.Attribute$<any>;

export function aria_rowspan(value: number): $vattr.Attribute$<any>;

export function aria_selected(value: boolean): $vattr.Attribute$<any>;

export function aria_setsize(value: number): $vattr.Attribute$<any>;

export function aria_sort(value: string): $vattr.Attribute$<any>;

export function aria_valuemax(value: string): $vattr.Attribute$<any>;

export function aria_valuemin(value: string): $vattr.Attribute$<any>;

export function aria_valuenow(value: string): $vattr.Attribute$<any>;

export function aria_valuetext(value: string): $vattr.Attribute$<any>;
