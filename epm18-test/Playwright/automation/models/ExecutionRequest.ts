export interface ExecutionRequest {

    action: ActionType;

    module: string;

    environment: string;

    payload: unknown;

}