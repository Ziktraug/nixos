type PermissionRule = {
  action: string;
  resource: string;
  effect: "allow" | "ask" | "deny";
};

type AgentDraft = {
  list: () => ReadonlyArray<{ id: string }>;
  update: (
    id: string,
    callback: (agent: { permissions: PermissionRule[] }) => void,
  ) => void;
};

type OpenCode2PluginContext = {
  agent: {
    transform: (callback: (draft: AgentDraft) => void) => Promise<unknown>;
  };
};

type OpenCode2Plugin = {
  id: string;
  setup: (context: OpenCode2PluginContext) => void | Promise<void>;
};

const policyRules = (): PermissionRule[] => [
  { action: "shell", resource: "*", effect: "ask" },
  {
    action: "shell",
    resource: 'agent-memory recall --repo "$PWD"',
    effect: "allow",
  },
  { action: "shell", resource: "rtk find .", effect: "allow" },
  { action: "shell", resource: "sudo*", effect: "deny" },
  { action: "shell", resource: "nixos-rebuild switch*", effect: "deny" },
  { action: "shell", resource: "nixos-rebuild boot*", effect: "deny" },
  { action: "shell", resource: "nix flake update*", effect: "deny" },
  { action: "shell", resource: "nix flake lock*", effect: "deny" },
  { action: "shell", resource: "git push*", effect: "deny" },
  { action: "shell", resource: "rtk git push*", effect: "deny" },
  { action: "shell", resource: "rtk nix flake update*", effect: "deny" },
  { action: "shell", resource: "rtk nix flake lock*", effect: "deny" },
  { action: "shell", resource: "rm -rf*", effect: "deny" },
  { action: "shell", resource: "rm -r*", effect: "deny" },
  { action: "edit", resource: "*", effect: "ask" },
  { action: "read", resource: ".env", effect: "deny" },
  { action: "read", resource: ".env.*", effect: "deny" },
  { action: "read", resource: "**/.env", effect: "deny" },
  { action: "read", resource: "**/.env.*", effect: "deny" },
  { action: "read", resource: "secrets", effect: "deny" },
  { action: "read", resource: "secrets/**", effect: "deny" },
  { action: "read", resource: "**/secrets", effect: "deny" },
  { action: "read", resource: "**/secrets/**", effect: "deny" },
  { action: "read", resource: "credentials", effect: "deny" },
  { action: "read", resource: "credentials/**", effect: "deny" },
  { action: "read", resource: "**/credentials", effect: "deny" },
  { action: "read", resource: "**/credentials/**", effect: "deny" },
  { action: "read", resource: ".git", effect: "deny" },
  { action: "read", resource: ".git/**", effect: "deny" },
  { action: "read", resource: "**/.git", effect: "deny" },
  { action: "read", resource: "**/.git/**", effect: "deny" },
  { action: "read", resource: "private", effect: "deny" },
  { action: "read", resource: "private/**", effect: "deny" },
  { action: "read", resource: "**/private", effect: "deny" },
  { action: "read", resource: "**/private/**", effect: "deny" },
  { action: "glob", resource: "*", effect: "ask" },
  { action: "grep", resource: "*", effect: "ask" },
  { action: "list", resource: "*", effect: "ask" },
];

const ruleKey = (rule: PermissionRule): string =>
  `${rule.action}\u0000${rule.resource}\u0000${rule.effect}`;

const secureAgents: OpenCode2Plugin = {
  id: "local.secure-agents",
  setup: async (context) => {
    await context.agent.transform((draft) => {
      const managed = new Set(policyRules().map(ruleKey));

      for (const item of draft.list()) {
        draft.update(item.id, (agent) => {
          agent.permissions = agent.permissions.filter(
            (rule) => !managed.has(ruleKey(rule)),
          );
          agent.permissions.push(...policyRules());
        });
      }
    });
  },
};

export default secureAgents;
