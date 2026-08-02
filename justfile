# App-owned. Runtime recipes come from Tooling/.
import 'Tooling/justfile'

demo role="owner":
    just run-sim -- -oneCartDemoUI -oneCartDemoRole {{role}}

demo-tab role="owner" tab="cart":
    just run-sim -- -oneCartDemoUI -oneCartDemoRole {{role}} -oneCartDemoTab {{tab}}
