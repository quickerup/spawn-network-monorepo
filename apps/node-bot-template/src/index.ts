import { routeCommand } from "./telegram/commandRouter";
import { NodeDO } from "./NodeDO";

export { NodeDO };

export default {
  async fetch(request: Request, env: any) {
    return routeCommand(request, env);
  }
};
