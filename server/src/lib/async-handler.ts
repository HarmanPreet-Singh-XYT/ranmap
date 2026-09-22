import type { NextFunction, Request, Response } from "express";

type Handler = (req: Request, res: Response, next: NextFunction) => Promise<unknown> | unknown;

/**
 * Express 4 does not catch rejected promises from `async` middleware/handlers,
 * so an unhandled rejection from one of them would crash the process (Node
 * treats unhandled rejections as fatal). Wrap every async handler with this so
 * rejections are forwarded to the terminal error handler instead.
 */
export function asyncHandler(handler: Handler) {
  return (req: Request, res: Response, next: NextFunction): void => {
    Promise.resolve(handler(req, res, next)).catch(next);
  };
}
