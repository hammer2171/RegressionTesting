export class ActionFactory {

    create(
        request: ExecutionRequest
    ): Action {

        switch(request.action){

            case ActionType.AddNode:

                return new AddNodeAction();

            case ActionType.MoveNode:

                return new MoveNodeAction();

            case ActionType.UpdateProperty:

                return new UpdatePropertyAction();

            default:

                throw new Error(
                    "Unsupported Action"
                );

        }

    }

}