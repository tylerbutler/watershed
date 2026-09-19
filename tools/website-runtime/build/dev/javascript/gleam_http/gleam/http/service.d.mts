import type * as $http from "../../gleam/http.d.mts";
import type * as $request from "../../gleam/http/request.d.mts";
import type * as $response from "../../gleam/http/response.d.mts";

export type Service = (x0: $request.Request$<any>) => $response.Response$<any>;

export type Middleware = (
  x0: (x0: $request.Request$<any>) => $response.Response$<any>
) => (x0: $request.Request$<any>) => $response.Response$<any>;

export function map_response_body<IKM, IKN, IKP>(
  service: (x0: IKM) => $response.Response$<IKN>,
  mapper: (x0: IKN) => IKP
): (x0: IKM) => $response.Response$<IKP>;

export function prepend_response_header<IKR, IKS>(
  service: (x0: IKR) => $response.Response$<IKS>,
  key: string,
  value: string
): (x0: IKR) => $response.Response$<IKS>;

export function method_override<ILE, ILG>(
  service: (x0: $request.Request$<ILE>) => ILG
): (x0: $request.Request$<ILE>) => ILG;
