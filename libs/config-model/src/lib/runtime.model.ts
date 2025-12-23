import { ConfigModel } from "./config.model";
import { InboundDataModel } from "./inbound.model";
import { OutboundDispatchPlan } from "./outbound.model";

export interface RuntimeModel {
    event: N8NEventModel<InboundDataModel>;
    config: ConfigModel;
    outbound: OutboundDispatchPlan;
}

export interface N8NEventModel<T> {
    headers: HeadersModel;
    params: ParamsModel;
    query: ParamsModel;
    body: T;
    webhookUrl: string;
    executionMode: string;
}

export interface HeadersModel {
    host: string;
    "user-agent": string;
    "content-length": string;
    accept: string;
    "accept-encoding": string;
    "cache-control": string;
    "content-type": string;
    "postman-token": string;
    "x-forwarded-port": string;
    "x-forwarded-proto": string;
    "x-forwarded-server": string;
}

export type ParamsModel = unknown
