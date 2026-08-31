/**
 * Probe plugin — minimal, follows https://opencode.ai/docs/plugins/ verbatim.
 * Registers one custom tool "hello_probe" that returns a fixed string.
 * No top-level await, single named export, sync module body.
 */
export const ProbePlugin = async () => {
  return {
    tool: {
      hello_probe: {
        description: "Returns the string 'probe ok' so we can confirm OpenCode loaded this plugin and registered its tools.",
        args: {},
        async execute() {
          return "probe ok";
        },
      },
    },
  };
};
