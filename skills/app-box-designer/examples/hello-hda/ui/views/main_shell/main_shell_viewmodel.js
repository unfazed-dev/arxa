export const surfaceId = 'main.shell';

// The shell renders the chrome; surfaces fill its {% block surface %}.
export const page = (c, h) =>
  h.render(c, 'ui/views/main_shell/main_shell_view.html');
