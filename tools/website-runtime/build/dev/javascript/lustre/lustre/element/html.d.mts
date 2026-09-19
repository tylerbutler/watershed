import type * as _ from "../../gleam.d.mts";
import type * as $vattr from "../../lustre/vdom/vattr.d.mts";
import type * as $vnode from "../../lustre/vdom/vnode.d.mts";

export function html<VBU>(
  attrs: _.List<$vattr.Attribute$<VBU>>,
  children: _.List<$vnode.Element$<VBU>>
): $vnode.Element$<VBU>;

export function text(content: string): $vnode.Element$<any>;

export function base<VCC>(attrs: _.List<$vattr.Attribute$<VCC>>): $vnode.Element$<
  VCC
>;

export function head<VCG>(
  attrs: _.List<$vattr.Attribute$<VCG>>,
  children: _.List<$vnode.Element$<VCG>>
): $vnode.Element$<VCG>;

export function link<VCM>(attrs: _.List<$vattr.Attribute$<VCM>>): $vnode.Element$<
  VCM
>;

export function meta<VCQ>(attrs: _.List<$vattr.Attribute$<VCQ>>): $vnode.Element$<
  VCQ
>;

export function style<VCU>(attrs: _.List<$vattr.Attribute$<VCU>>, css: string): $vnode.Element$<
  VCU
>;

export function title<VCY>(
  attrs: _.List<$vattr.Attribute$<VCY>>,
  content: string
): $vnode.Element$<VCY>;

export function body<VDC>(
  attrs: _.List<$vattr.Attribute$<VDC>>,
  children: _.List<$vnode.Element$<VDC>>
): $vnode.Element$<VDC>;

export function address<VDI>(
  attrs: _.List<$vattr.Attribute$<VDI>>,
  children: _.List<$vnode.Element$<VDI>>
): $vnode.Element$<VDI>;

export function article<VDO>(
  attrs: _.List<$vattr.Attribute$<VDO>>,
  children: _.List<$vnode.Element$<VDO>>
): $vnode.Element$<VDO>;

export function aside<VDU>(
  attrs: _.List<$vattr.Attribute$<VDU>>,
  children: _.List<$vnode.Element$<VDU>>
): $vnode.Element$<VDU>;

export function footer<VEA>(
  attrs: _.List<$vattr.Attribute$<VEA>>,
  children: _.List<$vnode.Element$<VEA>>
): $vnode.Element$<VEA>;

export function header<VEG>(
  attrs: _.List<$vattr.Attribute$<VEG>>,
  children: _.List<$vnode.Element$<VEG>>
): $vnode.Element$<VEG>;

export function h1<VEM>(
  attrs: _.List<$vattr.Attribute$<VEM>>,
  children: _.List<$vnode.Element$<VEM>>
): $vnode.Element$<VEM>;

export function h2<VES>(
  attrs: _.List<$vattr.Attribute$<VES>>,
  children: _.List<$vnode.Element$<VES>>
): $vnode.Element$<VES>;

export function h3<VEY>(
  attrs: _.List<$vattr.Attribute$<VEY>>,
  children: _.List<$vnode.Element$<VEY>>
): $vnode.Element$<VEY>;

export function h4<VFE>(
  attrs: _.List<$vattr.Attribute$<VFE>>,
  children: _.List<$vnode.Element$<VFE>>
): $vnode.Element$<VFE>;

export function h5<VFK>(
  attrs: _.List<$vattr.Attribute$<VFK>>,
  children: _.List<$vnode.Element$<VFK>>
): $vnode.Element$<VFK>;

export function h6<VFQ>(
  attrs: _.List<$vattr.Attribute$<VFQ>>,
  children: _.List<$vnode.Element$<VFQ>>
): $vnode.Element$<VFQ>;

export function hgroup<VFW>(
  attrs: _.List<$vattr.Attribute$<VFW>>,
  children: _.List<$vnode.Element$<VFW>>
): $vnode.Element$<VFW>;

export function main<VGC>(
  attrs: _.List<$vattr.Attribute$<VGC>>,
  children: _.List<$vnode.Element$<VGC>>
): $vnode.Element$<VGC>;

export function nav<VGI>(
  attrs: _.List<$vattr.Attribute$<VGI>>,
  children: _.List<$vnode.Element$<VGI>>
): $vnode.Element$<VGI>;

export function section<VGO>(
  attrs: _.List<$vattr.Attribute$<VGO>>,
  children: _.List<$vnode.Element$<VGO>>
): $vnode.Element$<VGO>;

export function search<VGU>(
  attrs: _.List<$vattr.Attribute$<VGU>>,
  children: _.List<$vnode.Element$<VGU>>
): $vnode.Element$<VGU>;

export function blockquote<VHA>(
  attrs: _.List<$vattr.Attribute$<VHA>>,
  children: _.List<$vnode.Element$<VHA>>
): $vnode.Element$<VHA>;

export function dd<VHG>(
  attrs: _.List<$vattr.Attribute$<VHG>>,
  children: _.List<$vnode.Element$<VHG>>
): $vnode.Element$<VHG>;

export function div<VHM>(
  attrs: _.List<$vattr.Attribute$<VHM>>,
  children: _.List<$vnode.Element$<VHM>>
): $vnode.Element$<VHM>;

export function dl<VHS>(
  attrs: _.List<$vattr.Attribute$<VHS>>,
  children: _.List<$vnode.Element$<VHS>>
): $vnode.Element$<VHS>;

export function dt<VHY>(
  attrs: _.List<$vattr.Attribute$<VHY>>,
  children: _.List<$vnode.Element$<VHY>>
): $vnode.Element$<VHY>;

export function figcaption<VIE>(
  attrs: _.List<$vattr.Attribute$<VIE>>,
  children: _.List<$vnode.Element$<VIE>>
): $vnode.Element$<VIE>;

export function figure<VIK>(
  attrs: _.List<$vattr.Attribute$<VIK>>,
  children: _.List<$vnode.Element$<VIK>>
): $vnode.Element$<VIK>;

export function hr<VIQ>(attrs: _.List<$vattr.Attribute$<VIQ>>): $vnode.Element$<
  VIQ
>;

export function li<VIU>(
  attrs: _.List<$vattr.Attribute$<VIU>>,
  children: _.List<$vnode.Element$<VIU>>
): $vnode.Element$<VIU>;

export function menu<VJA>(
  attrs: _.List<$vattr.Attribute$<VJA>>,
  children: _.List<$vnode.Element$<VJA>>
): $vnode.Element$<VJA>;

export function ol<VJG>(
  attrs: _.List<$vattr.Attribute$<VJG>>,
  children: _.List<$vnode.Element$<VJG>>
): $vnode.Element$<VJG>;

export function p<VJM>(
  attrs: _.List<$vattr.Attribute$<VJM>>,
  children: _.List<$vnode.Element$<VJM>>
): $vnode.Element$<VJM>;

export function pre<VJS>(
  attrs: _.List<$vattr.Attribute$<VJS>>,
  children: _.List<$vnode.Element$<VJS>>
): $vnode.Element$<VJS>;

export function ul<VJY>(
  attrs: _.List<$vattr.Attribute$<VJY>>,
  children: _.List<$vnode.Element$<VJY>>
): $vnode.Element$<VJY>;

export function a<VKE>(
  attrs: _.List<$vattr.Attribute$<VKE>>,
  children: _.List<$vnode.Element$<VKE>>
): $vnode.Element$<VKE>;

export function abbr<VKK>(
  attrs: _.List<$vattr.Attribute$<VKK>>,
  children: _.List<$vnode.Element$<VKK>>
): $vnode.Element$<VKK>;

export function b<VKQ>(
  attrs: _.List<$vattr.Attribute$<VKQ>>,
  children: _.List<$vnode.Element$<VKQ>>
): $vnode.Element$<VKQ>;

export function bdi<VKW>(
  attrs: _.List<$vattr.Attribute$<VKW>>,
  children: _.List<$vnode.Element$<VKW>>
): $vnode.Element$<VKW>;

export function bdo<VLC>(
  attrs: _.List<$vattr.Attribute$<VLC>>,
  children: _.List<$vnode.Element$<VLC>>
): $vnode.Element$<VLC>;

export function br<VLI>(attrs: _.List<$vattr.Attribute$<VLI>>): $vnode.Element$<
  VLI
>;

export function cite<VLM>(
  attrs: _.List<$vattr.Attribute$<VLM>>,
  children: _.List<$vnode.Element$<VLM>>
): $vnode.Element$<VLM>;

export function code<VLS>(
  attrs: _.List<$vattr.Attribute$<VLS>>,
  children: _.List<$vnode.Element$<VLS>>
): $vnode.Element$<VLS>;

export function data<VLY>(
  attrs: _.List<$vattr.Attribute$<VLY>>,
  children: _.List<$vnode.Element$<VLY>>
): $vnode.Element$<VLY>;

export function dfn<VME>(
  attrs: _.List<$vattr.Attribute$<VME>>,
  children: _.List<$vnode.Element$<VME>>
): $vnode.Element$<VME>;

export function em<VMK>(
  attrs: _.List<$vattr.Attribute$<VMK>>,
  children: _.List<$vnode.Element$<VMK>>
): $vnode.Element$<VMK>;

export function i<VMQ>(
  attrs: _.List<$vattr.Attribute$<VMQ>>,
  children: _.List<$vnode.Element$<VMQ>>
): $vnode.Element$<VMQ>;

export function kbd<VMW>(
  attrs: _.List<$vattr.Attribute$<VMW>>,
  children: _.List<$vnode.Element$<VMW>>
): $vnode.Element$<VMW>;

export function mark<VNC>(
  attrs: _.List<$vattr.Attribute$<VNC>>,
  children: _.List<$vnode.Element$<VNC>>
): $vnode.Element$<VNC>;

export function q<VNI>(
  attrs: _.List<$vattr.Attribute$<VNI>>,
  children: _.List<$vnode.Element$<VNI>>
): $vnode.Element$<VNI>;

export function rp<VNO>(
  attrs: _.List<$vattr.Attribute$<VNO>>,
  children: _.List<$vnode.Element$<VNO>>
): $vnode.Element$<VNO>;

export function rt<VNU>(
  attrs: _.List<$vattr.Attribute$<VNU>>,
  children: _.List<$vnode.Element$<VNU>>
): $vnode.Element$<VNU>;

export function ruby<VOA>(
  attrs: _.List<$vattr.Attribute$<VOA>>,
  children: _.List<$vnode.Element$<VOA>>
): $vnode.Element$<VOA>;

export function s<VOG>(
  attrs: _.List<$vattr.Attribute$<VOG>>,
  children: _.List<$vnode.Element$<VOG>>
): $vnode.Element$<VOG>;

export function samp<VOM>(
  attrs: _.List<$vattr.Attribute$<VOM>>,
  children: _.List<$vnode.Element$<VOM>>
): $vnode.Element$<VOM>;

export function small<VOS>(
  attrs: _.List<$vattr.Attribute$<VOS>>,
  children: _.List<$vnode.Element$<VOS>>
): $vnode.Element$<VOS>;

export function span<VOY>(
  attrs: _.List<$vattr.Attribute$<VOY>>,
  children: _.List<$vnode.Element$<VOY>>
): $vnode.Element$<VOY>;

export function strong<VPE>(
  attrs: _.List<$vattr.Attribute$<VPE>>,
  children: _.List<$vnode.Element$<VPE>>
): $vnode.Element$<VPE>;

export function sub<VPK>(
  attrs: _.List<$vattr.Attribute$<VPK>>,
  children: _.List<$vnode.Element$<VPK>>
): $vnode.Element$<VPK>;

export function sup<VPQ>(
  attrs: _.List<$vattr.Attribute$<VPQ>>,
  children: _.List<$vnode.Element$<VPQ>>
): $vnode.Element$<VPQ>;

export function time<VPW>(
  attrs: _.List<$vattr.Attribute$<VPW>>,
  children: _.List<$vnode.Element$<VPW>>
): $vnode.Element$<VPW>;

export function u<VQC>(
  attrs: _.List<$vattr.Attribute$<VQC>>,
  children: _.List<$vnode.Element$<VQC>>
): $vnode.Element$<VQC>;

export function var$<VQI>(
  attrs: _.List<$vattr.Attribute$<VQI>>,
  children: _.List<$vnode.Element$<VQI>>
): $vnode.Element$<VQI>;

export function wbr<VQO>(attrs: _.List<$vattr.Attribute$<VQO>>): $vnode.Element$<
  VQO
>;

export function area<VQS>(attrs: _.List<$vattr.Attribute$<VQS>>): $vnode.Element$<
  VQS
>;

export function audio<VQW>(
  attrs: _.List<$vattr.Attribute$<VQW>>,
  children: _.List<$vnode.Element$<VQW>>
): $vnode.Element$<VQW>;

export function img<VRC>(attrs: _.List<$vattr.Attribute$<VRC>>): $vnode.Element$<
  VRC
>;

export function map<VRG>(
  attrs: _.List<$vattr.Attribute$<VRG>>,
  children: _.List<$vnode.Element$<VRG>>
): $vnode.Element$<VRG>;

export function track<VRM>(attrs: _.List<$vattr.Attribute$<VRM>>): $vnode.Element$<
  VRM
>;

export function video<VRQ>(
  attrs: _.List<$vattr.Attribute$<VRQ>>,
  children: _.List<$vnode.Element$<VRQ>>
): $vnode.Element$<VRQ>;

export function embed<VRW>(attrs: _.List<$vattr.Attribute$<VRW>>): $vnode.Element$<
  VRW
>;

export function iframe<VSA>(attrs: _.List<$vattr.Attribute$<VSA>>): $vnode.Element$<
  VSA
>;

export function object<VSE>(attrs: _.List<$vattr.Attribute$<VSE>>): $vnode.Element$<
  VSE
>;

export function picture<VSI>(
  attrs: _.List<$vattr.Attribute$<VSI>>,
  children: _.List<$vnode.Element$<VSI>>
): $vnode.Element$<VSI>;

export function portal<VSO>(attrs: _.List<$vattr.Attribute$<VSO>>): $vnode.Element$<
  VSO
>;

export function source<VSS>(attrs: _.List<$vattr.Attribute$<VSS>>): $vnode.Element$<
  VSS
>;

export function math<VSW>(
  attrs: _.List<$vattr.Attribute$<VSW>>,
  children: _.List<$vnode.Element$<VSW>>
): $vnode.Element$<VSW>;

export function svg<VTC>(
  attrs: _.List<$vattr.Attribute$<VTC>>,
  children: _.List<$vnode.Element$<VTC>>
): $vnode.Element$<VTC>;

export function canvas<VTI>(attrs: _.List<$vattr.Attribute$<VTI>>): $vnode.Element$<
  VTI
>;

export function noscript<VTM>(
  attrs: _.List<$vattr.Attribute$<VTM>>,
  children: _.List<$vnode.Element$<VTM>>
): $vnode.Element$<VTM>;

export function script<VTS>(attrs: _.List<$vattr.Attribute$<VTS>>, js: string): $vnode.Element$<
  VTS
>;

export function del<VTW>(
  attrs: _.List<$vattr.Attribute$<VTW>>,
  children: _.List<$vnode.Element$<VTW>>
): $vnode.Element$<VTW>;

export function ins<VUC>(
  attrs: _.List<$vattr.Attribute$<VUC>>,
  children: _.List<$vnode.Element$<VUC>>
): $vnode.Element$<VUC>;

export function caption<VUI>(
  attrs: _.List<$vattr.Attribute$<VUI>>,
  children: _.List<$vnode.Element$<VUI>>
): $vnode.Element$<VUI>;

export function col<VUO>(attrs: _.List<$vattr.Attribute$<VUO>>): $vnode.Element$<
  VUO
>;

export function colgroup<VUS>(
  attrs: _.List<$vattr.Attribute$<VUS>>,
  children: _.List<$vnode.Element$<VUS>>
): $vnode.Element$<VUS>;

export function table<VUY>(
  attrs: _.List<$vattr.Attribute$<VUY>>,
  children: _.List<$vnode.Element$<VUY>>
): $vnode.Element$<VUY>;

export function tbody<VVE>(
  attrs: _.List<$vattr.Attribute$<VVE>>,
  children: _.List<$vnode.Element$<VVE>>
): $vnode.Element$<VVE>;

export function td<VVK>(
  attrs: _.List<$vattr.Attribute$<VVK>>,
  children: _.List<$vnode.Element$<VVK>>
): $vnode.Element$<VVK>;

export function tfoot<VVQ>(
  attrs: _.List<$vattr.Attribute$<VVQ>>,
  children: _.List<$vnode.Element$<VVQ>>
): $vnode.Element$<VVQ>;

export function th<VVW>(
  attrs: _.List<$vattr.Attribute$<VVW>>,
  children: _.List<$vnode.Element$<VVW>>
): $vnode.Element$<VVW>;

export function thead<VWC>(
  attrs: _.List<$vattr.Attribute$<VWC>>,
  children: _.List<$vnode.Element$<VWC>>
): $vnode.Element$<VWC>;

export function tr<VWI>(
  attrs: _.List<$vattr.Attribute$<VWI>>,
  children: _.List<$vnode.Element$<VWI>>
): $vnode.Element$<VWI>;

export function button<VWO>(
  attrs: _.List<$vattr.Attribute$<VWO>>,
  children: _.List<$vnode.Element$<VWO>>
): $vnode.Element$<VWO>;

export function datalist<VWU>(
  attrs: _.List<$vattr.Attribute$<VWU>>,
  children: _.List<$vnode.Element$<VWU>>
): $vnode.Element$<VWU>;

export function fieldset<VXA>(
  attrs: _.List<$vattr.Attribute$<VXA>>,
  children: _.List<$vnode.Element$<VXA>>
): $vnode.Element$<VXA>;

export function form<VXG>(
  attrs: _.List<$vattr.Attribute$<VXG>>,
  children: _.List<$vnode.Element$<VXG>>
): $vnode.Element$<VXG>;

export function input<VXM>(attrs: _.List<$vattr.Attribute$<VXM>>): $vnode.Element$<
  VXM
>;

export function label<VXQ>(
  attrs: _.List<$vattr.Attribute$<VXQ>>,
  children: _.List<$vnode.Element$<VXQ>>
): $vnode.Element$<VXQ>;

export function legend<VXW>(
  attrs: _.List<$vattr.Attribute$<VXW>>,
  children: _.List<$vnode.Element$<VXW>>
): $vnode.Element$<VXW>;

export function meter<VYC>(
  attrs: _.List<$vattr.Attribute$<VYC>>,
  children: _.List<$vnode.Element$<VYC>>
): $vnode.Element$<VYC>;

export function optgroup<VYI>(
  attrs: _.List<$vattr.Attribute$<VYI>>,
  children: _.List<$vnode.Element$<VYI>>
): $vnode.Element$<VYI>;

export function option<VYO>(
  attrs: _.List<$vattr.Attribute$<VYO>>,
  label: string
): $vnode.Element$<VYO>;

export function output<VYS>(
  attrs: _.List<$vattr.Attribute$<VYS>>,
  children: _.List<$vnode.Element$<VYS>>
): $vnode.Element$<VYS>;

export function progress<VYY>(
  attrs: _.List<$vattr.Attribute$<VYY>>,
  children: _.List<$vnode.Element$<VYY>>
): $vnode.Element$<VYY>;

export function select<VZE>(
  attrs: _.List<$vattr.Attribute$<VZE>>,
  children: _.List<$vnode.Element$<VZE>>
): $vnode.Element$<VZE>;

export function textarea<VZK>(
  attrs: _.List<$vattr.Attribute$<VZK>>,
  content: string
): $vnode.Element$<VZK>;

export function details<VZO>(
  attrs: _.List<$vattr.Attribute$<VZO>>,
  children: _.List<$vnode.Element$<VZO>>
): $vnode.Element$<VZO>;

export function dialog<VZU>(
  attrs: _.List<$vattr.Attribute$<VZU>>,
  children: _.List<$vnode.Element$<VZU>>
): $vnode.Element$<VZU>;

export function summary<WAA>(
  attrs: _.List<$vattr.Attribute$<WAA>>,
  children: _.List<$vnode.Element$<WAA>>
): $vnode.Element$<WAA>;

export function slot<WAG>(
  attrs: _.List<$vattr.Attribute$<WAG>>,
  fallback: _.List<$vnode.Element$<WAG>>
): $vnode.Element$<WAG>;

export function template<WAM>(
  attrs: _.List<$vattr.Attribute$<WAM>>,
  children: _.List<$vnode.Element$<WAM>>
): $vnode.Element$<WAM>;
