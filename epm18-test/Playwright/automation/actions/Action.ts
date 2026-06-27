export interface Action {

    execute(
        request: ExecutionRequest
    ): Promise<ExecutionResult>;

}