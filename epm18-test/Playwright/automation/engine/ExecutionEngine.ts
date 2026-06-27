export class ExecutionEngine {

    constructor(
        private readonly factory: ActionFactory
    ) {}

    async execute(
        request: ExecutionRequest
    ): Promise<ExecutionResult> {

        const action =
            this.factory.create(request);

        return await action.execute(request);

    }

}