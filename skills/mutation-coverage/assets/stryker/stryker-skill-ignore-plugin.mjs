/**
 * Stryker ignore plugin: skip mutants in code that unit tests never cover.
 *
 * Mutation testing here runs the *unit* suite (`yarn test`). Theme injection
 * (`static get lumoInjector()`) and styles (`static get styles()`) are covered
 * by visual regression tests instead of unit assertions, so mutants inside them
 * always survive — they are noise in the report and, with the command runner,
 * each one still costs a full suite run. Ignoring them removes them before they
 * are ever run (they show as "Ignored", excluded from the score) so the
 * survivors that remain are real unit-test gaps.
 *
 * Deliberately import-free: the plugin object below is exactly what
 * `declareClassPlugin(PluginKind.Ignore, name, Class)` from
 * `@stryker-mutator/api/plugin` returns ({ kind, name, injectableClass }), so
 * the plugin loads even when @stryker-mutator is not installed in the repo
 * (e.g. when Stryker itself runs via `npx --package @stryker-mutator/core`).
 *
 * https://stryker-mutator.io/docs/stryker-js/disable-mutants/#using-an-ignore-plugin
 */

const IGNORED_GETTERS = new Set(['lumoInjector', 'styles']);

class UntestedGetterIgnorer {
  // Receives the Babel NodePath of each mutant candidate during instrumentation.
  shouldIgnore(path) {
    const getter = path.findParent(
      (parent) =>
        parent.isClassMethod() &&
        parent.node.kind === 'get' &&
        parent.node.key.type === 'Identifier' &&
        IGNORED_GETTERS.has(parent.node.key.name),
    );
    if (getter) {
      return `Not covered by unit tests: static get ${getter.node.key.name}()`;
    }
    return undefined;
  }
}

export const strykerPlugins = [{ kind: 'Ignore', name: 'untested-getters', injectableClass: UntestedGetterIgnorer }];
