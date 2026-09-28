export const SIDEBAR_COOKIE_NAME = "memotrail-sidebar";

export function sidebarIsCollapsed(value: string | undefined) {
  return value === "collapsed";
}
