return {
  disable_default_quick_select_patterns = true,
  quick_select_patterns = {
    'https?://[^"\' ]+', -- url
    'sha256-\\S{44}', -- sha256 another
    'AQ\\S{38}', -- CephX secret
    '[0-9a-f]{7,40}', -- sha1
    'sha256:[A-Za-z0-9]{52}', -- sha256
    '%d+%.%d+%.%d+%.%d+', -- IPv4
    '[A-Fa-f0-9:]+::?[A-Fa-f0-9:]*', -- IPv6
    '[a-z0-9-]+.[a-z0-9]+.[a-z0-9]+.[a-z0-9]+ ', -- inno FQDN
    '[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+.[a-zA-Z0-9.-]+', -- simple e-mail
    '\'(\\S[^\']*\\S)\'', -- single quoted text
    '"(\\S[^"]*\\S)"', -- double quoted text
    '~?/?[a-zA-Z0-9_/.-]+', -- path
    '(?<=\\)\\s)[^\\s]+', -- git branch name on my prompt
    '(?<=~>\\s).*?(?=\\s*(?:\\(|\\[))', -- stuff after ~> because that is the prompt
    -- '%s(.*)%s', -- anything else covered with whitespace
  },
}
