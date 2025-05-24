### Nix flakes
A nix flake is a directory with the files `flake.nix` and `flake.lock`. Most often, these files are contained in the top-level directory of a git repository, making the git repository a nix flake. These flakes can declare inputs in the `flake.nix` file whose versions are locked in the respective `flake.lock` file. At evaluation time, these inputs are resolved and used to evaluate the outputs of a flake. The outputs can consist of, e.g., nix derivations or `nix develop` shells. A user can interact with these flake outputs by using the nix CLI such as, e.g., `nix build`, `nix develop`, `nix profile install`, and many more.

Besides supplying the outputs of a flake to a user, a flake can also be considered as an input for another flake. Consider the following snippet of a flake file, where the input `k-framework` is declared that provides the nix flake that is located in the top-level directory of the git repository `https://github.com/runtimeverification/k` at revision/tag `v7.1.241`. In addition, a second input called `nixpkgs` is declared as well:
```nix
inputs = {
  k-framework.url = "github:runtimeverification/k/v7.1.241";
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
};
```

Assuming that `k-framework` itself also declares an input called `nixpkgs`, we get the following dependency graph:
```
+----------------+                    
|    nixpkgs     |                    
+----------------+                    
        ^                             
        |                             
        |                             
        |                             
+----------------+  +----------------+
|       k        |  |    nixpkgs     |
+----------------+  +----------------+
            ^            ^            
             \          /             
              \        /              
               \      /               
          +----------------+          
          | my-first-flake |          
          +----------------+          
```

The flake that declares another flake as an input can actually alter the transitive inputs of said input by using the `follows` attribute, bypassing the version locks of the `flake.lock` file of an input. This is useful for fixing common inputs to the same revision, because otherwise multilpe copies and instances would be required. One such common flake input is `nixpkgs`. Using multiple different instances of `nixpkgs` would drastically increase the required disk space for built derivations and its dependencies and also potentially increase build time. Therefore, please consider the following example where the transitive input `nixpkgs` is altered to follow the same revision as specified in the top-level flake. Specifically, specifying revision of transitive nix flake inputs uses `follows` in a *bottom-up* fashion:
```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  k-framework = {
    url = "github:runtimeverification/k/v7.1.241";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```
This results in the following dependency tree, where both `k` and `my-first-flake` always use the same revision of `nixpkgs` that is specified in `my-first-flake`:
```
                    +----------------+
                    |    nixpkgs     |
                    +----------------+
                    ^        ^        
                   /        /         
                  /        /          
                 /        /           
+----------------+       /            
|       k        |      /             
+----------------+     /              
            ^         /               
             \       /                
              \     /                 
               \   /                  
          +----------------+          
          | my-first-flake |          
          +----------------+          
```

`follows` can also be used in a *top-down* fashion, where newly declared inputs are configured to follow the revision of transitive inputs:
```nix
inputs = {
  k-framework.url = "github:runtimeverification/k/v7.1.241";
  nixpkgs.follows = "k-framework/nixpkgs";
};
```

Though please note that specyfing `nixpkgs` with `follows` in a *top-down* fashion is discouraged. For that purpose, please consider another flake `my-second-flake` that declares `my-first-flake` as an input including multiple other inputs that all declare `nixpkgs` as an input:
```
                    +----------------+                                 
                    |    nixpkgs     |<-                               
                    +----------------+< \-                             
                    ^ ^         ^  ^   \- \--                          
                   /  |         |  |     \   \--                       
                  /   |         |   \     \     \-                     
                 /    |         |   |      \-     \-                   
+----------------+    |         |   |        \     +----------------+  
|       k        |    |         |    \        \    |     b          |  
+----------------+    |         |    |         \-  +----------------+  
            ^         |         |    |           \      ^              
             \        |         |    |            \      \             
              \       |         |     \            \-     \            
               \      |         |     |              \     \           
          +----------------+    | +----------------+ +----------------+
          | my-first-flake |    | |       c        | |       a        |
          +----------------+    | +----------------+ +----------------+
                      ^         |         ^          ^                 
                       \        |        /          /                  
                        \       |       /          /                   
                         \      |      /          /                    
                          \     |     /          /                     
                           \    |    /          /                      
                            \   |   /          /                       
                             +----------------+                        
                             |my-second-flake |                        
                             +----------------+                        
```

We still want to only make use of one instance and revision of `nixpkgs`, but `my-second-flake` can only follow the `nixpkgs` of one of its multiple inputs. For the other inputs, overriding their `nixpkgs` input revision with a *bottom-up* style `follows` will still be required. Now, please consider the following nix code that does exactly that, while assuming that all inputs make use of *top-down* `follows` of `nixpkgs` that is discouraged:
```nix
inputs = {
  # declare inputs
  my-first-flake.url = "github:runtimeverification/my-first-flake";
  a.url = "github:runtimeverification/a";
  c.url = "github:runtimeverification/c";
  # declare nixpkgs input that follows the `nixpkgs` specified in `c`
  nixpkgs.follows = "c/nixpkgs";
  # make `nixpkgs` of `my-first-flake` follow the one specified in `c`
  my-first-flake.inputs.k.inputs.nixpkgs.follows = "nixpkgs";
  # make `nixpkgs` of `a` follow the one specified in `c`
  a.inputs.b.inputs.nixpkgs.follows = "nixpkgs";
};
```

First of all, as previously discussed, we cannot avoid the use of *bottom-up* `follows` when using *top-down* `follows`. Second, in order to use the required *bottom-up* follows, we require internal implementation details of declared inputs. If we were to miss any inputs, e.g., because new ones were introduced later on, we would end up with multiple potentially different instances of `nixpkgs`. Lastly, this code is unnecessarily hard to read. Now, let us assume that all our flakes all use *bottom-up* `follows` to specify the revision of `nixpkgs`, including `my-second-flake`:
```nix
inputs = {
  # declare inputs
  my-first-flake.url = "github:runtimeverification/my-first-flake";
  a.url = "github:runtimeverification/a";
  c.url = "github:runtimeverification/c";
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # make inputs use the same `nixpkgs` as specified in this flake
  my-first-flake.inputs.nixpkgs.follows = "nixpkgs";
  a.inputs.nixpkgs.follows = "nixpkgs";
  c.inputs.nixpkgs.follows = "nixpkgs";
};
```

This time, we don't have to reference transitive inputs and as long as all flakes consistently use *bottom-up* `follows`, we can be sure that only one instance of `nixpkgs` is being used. The code is also easier to read.

A disadvantage of this pattern is, though, that all flakes have to actively specify and maintain a revision of `nixpkgs` on their own. At runtime verification, we have multiple flakes that are used standalone as well as declared as inputs respectively. E.g., consider the following subset of transitive inputs of the `kontrol` flake: `kontrol` -> `evm-semantics` -> `k` -> `haskell-backend`. Having each of these flakes specify a different revision of `nixpkgs` would result in the collective size of dependencies for derivations of all of these flakes to increase. For this purpose, we make use of another pattern and the nix flake `rv-nix-tools`.

### rv-nix-tools
`github:runtimeverification/rv-nix-tools` is a nix flake that contains nix library code that is used throughout runtime verification repositories. It also declares `nixpkgs` as an input to a fixed revision that is updated periodically with a GitHub workflow from the `devops` repository by opening update pull requests.

As previosly discussed, we don't want runtime verification flakes to maintain their own revision of `nixpkgs`. Therefore, we can instead specify `rv-nix-tools` as an input and make `nixpkgs` follow the `nixpkgs` specified by `rv-nix-tool`. By doing so, we maintain the revision of `rv-nix-tools` instead of `nixpkgs`. As long as all flakes specify an up-to-date revision of `rv-nix-tools`, all flakes will use the same revision of `nixpkgs`. This, again, makes use *top-down* `follows`, but with a maximum depth of 1. E.g., please consider the previous example that makes use of this new pattern:
```nix
inputs = {
  # declare inputs
  my-first-flake.url = "github:runtimeverification/my-first-flake";
  a.url = "github:runtimeverification/a";
  c.url = "github:runtimeverification/c";
  rv-nix-tools.url = "github:runtimeverification/rv-nix-tools";
  # declare input `nixpkgs` that follows the `nixpkgs` specified in `rv-nix-tools`
  nixpkgs.follows = "rv-nix-tools/nixpkgs";
  # make inputs use the same `nixpkgs` as specified in `rv-nix-tools`
  my-first-flake.inputs.nixpkgs.follows = "nixpkgs";
  a.inputs.nixpkgs.follows = "nixpkgs";
  c.inputs.nixpkgs.follows = "nixpkgs";
};
```

### resolve build conflicts during updates of `nixpkgs`
Please consider the previous example of `my-second-flake`, but this time making use of *bottom-up* `follows`. For simplicity, `rv-nix-tools` was left out of this example:
```
                    +----------------+                                 
                    |    nixpkgs     |<-                               
                    +----------------+< \-                             
                    ^ ^         ^  ^   \- \--                          
                   /  |         |  |     \   \--                       
                  /   |         |   \     \     \-                     
                 /    |         |   |      \-     \-                   
+----------------+    |         |   |        \     +----------------+  
|       k        |    |         |    \        \    |     b          |  
+----------------+    |         |    |         \-  +----------------+  
            ^         |         |    |           \      ^              
             \        |         |    |            \      \             
              \       |         |     \            \-     \            
               \      |         |     |              \     \           
          +----------------+    | +----------------+ +----------------+
          | my-first-flake |    | |       c        | |       a        |
          +----------------+    | +----------------+ +----------------+
                      ^         |         ^          ^                 
                       \        |        /          /                  
                        \       |       /          /                   
                         \      |      /          /                    
                          \     |     /          /                     
                           \    |    /          /                      
                            \   |   /          /                       
                             +----------------+                        
                             |my-second-flake |                        
                             +----------------+                        
```
Imagine that we have two update pull requests pending: one for `my-first-flake` and the other for the `nixpkgs` that is specified by `my-second-flake`. Additionally, imagine the potential edge-case, where both pull requests break without the other being applied beforehand. E.g., `my-first-flake` could have updated `nixpkgs` before and changed code due to breakage by a new revision of `nixpkgs`. This new change now also breaks old revision of `nixpkgs`. Therefore, the update of `my-first-flake` breaks `my-second-flake` that enforces the use of an older revision of `nixpkgs`. On the other hand, updating `nixpkgs` in `my-second-flake` causes the older revision of `my-first-flake` to break, therefore requiring the update pull request of `my-first-flake`.

This kind of deadlock can be resolved by temporarily allowing multiple instances of `nixpkgs` in `my-second-flake`. To do so, the update pull request of `my-first-flake` has to be augmented with a commit that temporarily removes the line that overrides the revision of `nixpkgs` used in `my-first-flake`. E.g., change:
```nix
inputs = {
  # declare inputs
  my-first-flake.url = "github:runtimeverification/my-first-flake";
  a.url = "github:runtimeverification/a";
  c.url = "github:runtimeverification/c";
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # make inputs use the same `nixpkgs` as specified in this flake
  my-first-flake.inputs.nixpkgs.follows = "nixpkgs";
  a.inputs.nixpkgs.follows = "nixpkgs";
  c.inputs.nixpkgs.follows = "nixpkgs";
};
```
to
```nix
inputs = {
  # declare inputs
  my-first-flake.url = "github:runtimeverification/my-first-flake";
  a.url = "github:runtimeverification/a";
  c.url = "github:runtimeverification/c";
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # make inputs use the same `nixpkgs` as specified in this flake
  # TODO: uncomment the following line again, once `nixpkgs` was updated to a revision that does not break `my-first-flake`
  # my-first-flake.inputs.nixpkgs.follows = "nixpkgs";
  a.inputs.nixpkgs.follows = "nixpkgs";
  c.inputs.nixpkgs.follows = "nixpkgs";
};
```
This will make the update pull request of `my-first-flake` not break anymore. After merging the update pull request of `my-first-flake`, the update pull request of `nixpkgs` will also not break anymore. The update pull request of `nixpkgs` then has to be augmented with a commit that re-introduces the `follows` line that makes `my-first-flake` use the same revision of `nixpkgs` as `my-second-flake`: `my-first-flake.inputs.nixpkgs.follows = "nixpkgs";`.


