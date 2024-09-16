# Nix at RV

## What is nix?

>  Nix is a purely functional package manager and deployment system for POSIX. 

> Nix makes no assumptions about the global state of the system. 

> In Nix there is the notion of a _derivation_ rather than a package.

## No, but really, what is nix?

It's a bunch of things:

* The nix expression language
* Nix derivations
* The nix store
* A bunch of utilities to work with the nix language and store

## The nix language

The Nix expression language is a pure, lazy, functional language. The language is not a full-featured, general-purpose language. Its main job is to describe packages...

### Pure

Purity means that operations in the language don't have side effects (for instance, there is no variable assignment). Laziness means that arguments to functions are evaluated only when they are needed. 

### Functional

Functional means that functions are “normal” values that can be passed around and manipulated in interesting ways. 

### Lazy

Nix evaluates expressions lazily, which means it will only compute a certain value if it needs it.

## Then nix repl

To get a feel for the language, you can launch `nix repl` which allows you to build and evaluate nix expressions. This is a helpful resource for quickly getting an overview of the language features: https://learnxinyminutes.com/docs/nix/

There are certain features of the language which make it seem rather strange. Some of these include:

### Functions

Functions in nix are defined in a few different ways. The most basic function, the identity function is written as `a: a`

```nix
nix-repl> a: a
«lambda @ (string):1:1»
```

This is subtly different to:

```nix
nix-repl> {a}: a
«lambda @ (string):1:1»
```

Whereas in the first instance, the function takes some argument a and simply returns it, the second function takes a **set** (also called an attr(ibute) set in nix lingo and usually referred to as a dictionary in other languages) with the key "a" and returns the value at "a".

This can be demonstrated by applying the two functions to a simple argument. In the first instance, `(a: a) 2` evaluates to `2`:

```nix
nix-repl> (a: a) 2
2
```

However, we get an error with the second function:

```nix
nix-repl> ({a}: a) 2
error: value is an integer while a set was expected

       at «string»:1:1:

            1| ({a}: a) 2
             | ^
```

To correctly evaluate, we need to give the function a set, containing "a"

```nix
nix-repl> ({a}: a) { a = 2; }
2
```

### Lists don't use commas

This is a bit like bash and can throw people, especially since, function application also uses juxtaposition, see the two expressions below:

```nix
nix-repl> [ ({a}: a) { a = 2; } ]
[ «lambda @ (string):1:4» { ... } ]

nix-repl> [ (({a}: a) { a = 2; }) ]
[ 2 ]
```

### `inherit` keyword

The inherit keyword is used quite often and can be confusing to understand, but it is really just some syntactic sugar for the following:

```nix
{ inherit foo; } == { foo = foo; }
{ inherit foo baz; } == { foo = foo; baz = baz; }
{ inherit (bar) foo; } == { foo = bar.foo; }
```

Another bit of sugar that's common is to write

```nix
a.b = 2;
```

which is equivalent to 
```nix
a = { b = 2; };
```

We can test these features out on the following expression

```nix
nix-repl> let a.b = 2; in { inherit (a) b; }
{ b = 2; }
```

### `with` keyword

`with` is another bit of syntactic sugar, similar to opening/bringing a module into scope. Given an expression with variables `bar` and `baz`, the same expression prefixed with a `with foo;` will automatically replace all occurrences of said variables with `foo.bar` and `foo.baz`, i.e.: 

```nix
with foo; ... bar ... == ... foo.bar ...
```

Here is an actual example:

```nix
nix-repl> let a.b = 2; in with a; b
2
```

You will often see expressions like this in our nix files:

```nix
...
buildInputs = with pkgs; [ gcc clang java ]
...
```

### `import` keyword

The `import` keyword takes a path to a `.nix` file and loads the expression inside the file. If you specify a path without a `.nix` file, nix will look for and evaluate a `default.nix` file at that path. There is a special syntax reserved for importing [`nixpkgs`](https://github.com/NixOS/nixpkgs), the central repository of nix packages.

```nix
nix-repl> let pkgs = import <nixpkgs>; in pkgs
«lambda @ /nix/store/x5k4pqinh3ijsmvaa4pzypaw7hvdjhl5-nixpkgs/nixpkgs/pkgs/top-level/impure.nix:14:1»
```

Note that in the example above, `import <nixpkgs>` loads an expression which is a function, as evidenced by the `«lambda ...`. When we want to actually use any of the packages, we have to pass an attrset to this function (which can be empty or contain attributes such as which system we want the packages for, e.g. linux/mac). After we pass in the attrset, the function in turn returns an attrset of package derivations (see below what we mean by a derivation):


```nix
nix-repl> let pkgs = import <nixpkgs> {}; in pkgs.hello
«derivation /nix/store/fmm0zf4qa6yfy55byw8z40sqnfdyarzj-hello-2.12.drv»
```

### Laziness

As mentioned above, nix is lazy. What this means is that it will only do the bare minimum to evaluate an expression. This can be demonstrated by the following example

```nix
nix-repl> (a: b: a) 2 (throw "foo")
2

nix-repl> (a: b: a) (throw "foo") 2
error: foo
```

In a strict language, the arguments to the function would be evaluated first causing the error "foo" to be thrown, no matter the order of the arguments. 


## The nix store

The nix store is usually located at `/nix/store/` and is essentially just a database of things. These things will usually be:

* Source files for projects we are building
* Compiled outputs, such as binaries, libraries or any other files
* Nix derivations (files ending in `.drv`)

The nix store isn't just a folder containing some files. Firstly, files can only be added to it in a principled way, namely via interaction with the nix tools we will describe later. There are multiple reasons for this restriction, namely because the store not only stores the data but also records metadata about each store entry. The second reason is that the store is immutable and the entries are added under a path which is their cryptographic hash, computed by nix on addition.

To see what's in your nix store, you can run 

```
ls /nix/store
```

The (very) truncated contents of mine are:

```
...
zzsa1m9i7hsrgn76g193612il67y19qs-ghc-shell-for-kore-env
zzvc1bkja23m8ka2n02zbycnk9ys0ppk-gitrev-1.3.1.drv
zzwg87ixln5zn8wdqn3w1qsnxqx25am7-iproute-lib-iproute-1.7.12.drv
zzwjsw4v0y1pjmwrpyvkc736n27mv4gh-base-orphans-lib-base-orphans-0.8.6-haddock
zzyc2ky4ylgc2l8af76x70256q56drvw-b498303066a63a203d24f739b2d2e0e56dca70d1.patch.drv
zzycdl5zdl6j25rpdfvrz2iic3p2nf7b-Pygments-2.12.0.tar.gz.drv
zzyzzfvqgpvycjlnra4jj194vp8kp793-mvn.drv
zzz6xgg491662l780fs1wi4i8mm198p6-maven-parent-31.pom.drv
zzzqyzi4x89br7rff5vqh2hbc21g05dg-time-compat-lib-time-compat-1.9.5-haddock-doc
```

Notice that there are numerous files and folders, with a human-readable file name suffix such as `Pygments-2.12.0.tar.gz.drv`, prepended with a cryptographic hash `zzycdl5zdl6j25rpdfvrz2iic3p2nf7b`. One key feature of the nix store is that it is immutable. Therefore, any new file or folder added gets a unique name, even if the human-readable name is the same (unless of course the contents of the file are the same and therefore have the same hash).

Because the nix store isn't just a folder, but rather a database, we can query it for various information. For example, the store maintains the information on any connections/dependencies each entry in the store has on other entries (in fact the store ~~is~~ should be a DAG...I think). We can query this information via

```
nix-store -q --tree /nix/store/zzycdl5zdl6j25rpdfvrz2iic3p2nf7b-Pygments-2.12.0.tar.gz.drv

/nix/store/zzycdl5zdl6j25rpdfvrz2iic3p2nf7b-Pygments-2.12.0.tar.gz.drv
├───/nix/store/720ikgx7yaapyb8hvi8lkicjqwzcx3xr-builder.sh
├───/nix/store/7kcayxwk8khycxw1agmcyfm9vpsqpw4s-bootstrap-tools.drv
│   ├───/nix/store/3glray2y14jpk1h6i599py7jdn3j2vns-mkdir.drv
│   ├───/nix/store/50ql5q0raqkcydmpi6wqvnhs9hpdgg5f-cpio.drv
│   ├───/nix/store/81xahsrhpn9mbaslgi5sz7gsqra747d4-unpack-bootstrap-tools-aarch64.sh
│   ├───/nix/store/fzbk4fnbjqhr0l1scx5fspsx5najbrbm-bootstrap-tools.cpio.bz2.drv
│   ├───/nix/store/gxzl4vmccqj89yh7kz62frkxzgdpkxmp-sh.drv
│   └───/nix/store/pjbpvdy0gais8nc4sj3kwpniq8mgkb42-bzip2.drv
├───/nix/store/qq0pdil3cglk6yzzspm008k4rhi10mkl-bootstrap-stage0-stdenv-darwin.drv
│   ├───/nix/store/1i5y55x4b4m9qkx5dqbmr1r6bvrqbanw-multiple-outputs.sh
│   ├───/nix/store/55szi95529di53hsb4n39svvzmgr63hg-setup.sh
│   ├───/nix/store/59jmzisg8fkm9c125fw384dqq1np602l-move-docs.sh
│   ├───/nix/store/7kcayxwk8khycxw1agmcyfm9vpsqpw4s-bootstrap-tools.drv [...]
│   ├───/nix/store/bkxq1nfi6grmww5756ynr1aph7w04lkk-strip.sh
│   ├───/nix/store/bnj8d7mvbkg3vdb07yz74yhl3g107qq5-patch-shebangs.sh
│   ├───/nix/store/cickvswrvann041nqxb0rxilc46svw1n-prune-libtool-files.sh
│   ├───/nix/store/ckzrg0f0bdyx8rf703nc61r3hz5yys9q-builder.sh
│   ├───/nix/store/fyaryjvghbkpfnsyw97hb3lyb37s1pd6-move-lib64.sh
│   ├───/nix/store/kd4xwxjpjxi71jkm6ka0np72if9rm3y0-move-sbin.sh
│   ├───/nix/store/kxw6q8v6isaqjm702d71n2421cxamq68-make-symlinks-relative.sh
│   ├───/nix/store/m54bmrhj6fqz8nds5zcj97w9s9bckc9v-compress-man-pages.sh
│   ├───/nix/store/ngg1cv31c8c7bcm2n8ww4g06nq7s4zhm-set-source-date-epoch-to-latest.sh
│   └───/nix/store/wlwcf1nw2b21m4gghj70hbg1v7x53ld8-reproducible-builds.sh
└───/nix/store/9dbpgll89l1gxpa01a4w11v1gjxmz5y7-mirrors-list.drv
    ├───/nix/store/7kcayxwk8khycxw1agmcyfm9vpsqpw4s-bootstrap-tools.drv [...]
    ├───/nix/store/qq0pdil3cglk6yzzspm008k4rhi10mkl-bootstrap-stage0-stdenv-darwin.drv [...]
    └───/nix/store/ycwm35msmsdi2qgjax1slmjffsmwy8am-write-mirror-list.sh
```

This tells us that `zzycdl5zdl6j25rpdfvrz2iic3p2nf7b-Pygments-2.12.0.tar.gz.drv` somehow depends on all these other files in the store and it would therefore be a bad idea to delete any of them whilst this particular file is still in the store.

## The nix derivation

We have seen quite a few `.drv` files in the store. But what are they? Why are they? (When are they?) All great questions. Let's start with what. Ultimately, nix is meant to be a package manager. This means it should be capable of building software and letting the user execute the built binaries. In order to do this, nix needs a recipe for building the software. Such a recipe is called the derivation and it is stored in the nix store with the `.drv` extension. Let's have a look at a sample derivation:

```bash
nix show-derivation /nix/store/sc6ax6ag43vjs8rw65zzzx2rv4hmjmcl-hello-2.12.drv
{
  "/nix/store/sc6ax6ag43vjs8rw65zzzx2rv4hmjmcl-hello-2.12.drv": {
    "outputs": {
      "out": {
        "path": "/nix/store/ykj5hrkd4fqpvlzr2hghq4h7a45zqy1s-hello-2.12"
      }
    },
    "inputSrcs": [
      "/nix/store/9krlzvny65gdc8s7kpb6lkx8cd02c25b-default-builder.sh"
    ],
    "inputDrvs": {
      "/nix/store/l01z223v9ij1kjpm84f9hj4g3kcd5vzj-hello-2.12.tar.gz.drv": [
        "out"
      ],
      "/nix/store/l4k20i8w80gafnmabjvl1z72bhqwim2j-bash-5.1-p16.drv": [
        "out"
      ],
      "/nix/store/rkscx0pb9i06f2ham82q49idn8wlbxzd-stdenv-darwin.drv": [
        "out"
      ]
    },
    "system": "aarch64-darwin",
    "builder": "/nix/store/gzcbs0pkzsv1q3rngvf4i53z3vv7vxl4-bash-5.1-p16/bin/bash",
    "args": [
      "-e",
      "/nix/store/9krlzvny65gdc8s7kpb6lkx8cd02c25b-default-builder.sh"
    ],
    "env": {
      "__darwinAllowLocalNetworking": "",
      "__impureHostDeps": "/bin/sh /usr/lib/libSystem.B.dylib /usr/lib/system/libunc.dylib /dev/zero /dev/random /dev/urandom /bin/sh",
      "__propagatedImpureHostDeps": "",
      "__propagatedSandboxProfile": "",
      "__sandboxProfile": "",
      "buildInputs": "",
      "builder": "/nix/store/gzcbs0pkzsv1q3rngvf4i53z3vv7vxl4-bash-5.1-p16/bin/bash",
      "configureFlags": "",
      "depsBuildBuild": "",
      "depsBuildBuildPropagated": "",
      "depsBuildTarget": "",
      "depsBuildTargetPropagated": "",
      "depsHostHost": "",
      "depsHostHostPropagated": "",
      "depsTargetTarget": "",
      "depsTargetTargetPropagated": "",
      "doCheck": "1",
      "doInstallCheck": "",
      "name": "hello-2.12",
      "nativeBuildInputs": "",
      "out": "/nix/store/ykj5hrkd4fqpvlzr2hghq4h7a45zqy1s-hello-2.12",
      "outputs": "out",
      "patches": "",
      "pname": "hello",
      "propagatedBuildInputs": "",
      "propagatedNativeBuildInputs": "",
      "src": "/nix/store/8nqv6kshb3vs5q5bs2k600xpj5bkavkc-hello-2.12.tar.gz",
      "stdenv": "/nix/store/3r5i3gwh8asv63a0375h84m4h4dr5dy5-stdenv-darwin",
      "strictDeps": "",
      "system": "aarch64-darwin",
      "version": "2.12"
    }
  }
}
```

As you can see, a `.drv` file is nothing but a humble JSON file, containing some stuff, such as:

* `outputs` - where should we store whatever this derivation builds
* `inputSrcs`/`inputDrvs` - files/derivations for other tools we may depend on for building or at runtime
* `env.src` - source files we need to build this derivations
* `env.buildCommand` - bash commands to build the output, e.g.:

    ```
    "buildCommand": "mkdir -p $out/bin\nmakeWrapper /nix/store/hggyjs5haxxpykf3pqb6580ll667z10z-apache-maven-3.8.3/bin/mvn $out/bin/mvn --add-flags \"--settings /nix/store/5kivgfannc5qz07pxksf2s38diflzd5x-settings.xml\"\n"
    ```

## From a nix expression to a nix derivation

We have now seen the three main components of nix. The expression language, the derivations and the store. In order to go from the nix expression in a `.nix` file, to a `.drv` derivation we have to first instantiate a nix expression that is a derivation. As we have seen earlier, `pkgs.hello` had the type of `«derivation ...»`, i.e. not every nix expression will be a valid derivation, e.g. `2 + 2` a derivation aint!

So how do we create something of the type `«derivation ...»`? We have to use one of the functions in the nix libraries, which produces a derivation. This can either be the [`builtin.derivation`](https://nixos.org/manual/nix/stable/expressions/derivations.html) function or more commonly the [`stdenv.mkDerivation`](https://nixos.org/manual/nixpkgs/stable/#sec-using-stdenv) function found in [`nixpkgs`](https://github.com/NixOS/nixpkgs). Often we will use other functions such as [`mavenix.buildMaven`](https://github.com/runtimeverification/k/blob/7e8d5610dbcc85297996876a4e0e1702dedcaf5e/nix/k.nix) which is just a custom wraped version of `stdenv.mkDerivation` (you can see this here: https://github.com/nix-community/mavenix/blob/ce9ddfd7f361190e8e8dcfaf6b8282eebbb3c7cb/mavenix.nix#L199).

Once we have the derivation, we can ask nix to build it for us and store the result in the nix store. Whilst we can split these two steps up, we usually want to evaluate our nix expression into a derivation and immediately build it. Here is a helpful diagram of how a nix expression can be turned into some resulting output:

![](https://i.stack.imgur.com/NqxsO.png)

## Nix flakes

Nix flakes are a new feature of nix. They mainly do the following:

1) Clean up the CLI to make it less confusing (IMO)
2) Help with the organisation of different derivations within a single repo/project
2) Deal with the issue of "pinning" packages

### What is "pinning"

So far, we have not really talked about the main nixpkgs repository. If you go to https://search.nixos.org/packages, you can search through all the available packages that you can build an use from `nixpkgs`. You may notice that there is an option of a channel, currently at version `22.05` or `unstable`. These channels carry different versions of packages and are themselves updated with bug fixes and minor versions. This poses a problem because building anything asaint `nixpkgs` suddenly doesn't seem so deterministic. If I build my derivation against this week's version of nixpkgs, who's to say that it won't be broken next week when a new version gets used by someone else? To fix this issue, we can specify exactly which version of nixpkgs we want to use to build our derivation. A popular way to do this pinning has been to use [`niv`](https://github.com/nmattia/niv), a program that can generate pinned dependencies on `nixpkgs` or any derivations you may wish to use, which live somewhere else, usually a git(hub) repository. 

Nix flakes subsume this functionality and one no longer needs to use niv to manage these dependencies.

### A simple flake

A nix flake is a file called `flake.nix`, which is just an attrset with (at least) two keys, `input` and `outputs`:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
  };

  outputs = { self, nixpkgs }: {
    defaultPackage.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.hello;
  };
}
```

The `inputs` describe all the "things" we need for building the `outputs` section of the file.

The `outputs` must be a function with the following schema:

```nix
{ self, ... }@inputs:
{
  # Executed by `nix flake check`
  checks."<system>"."<name>" = derivation;
  # Executed by `nix build .#<name>`
  packages."<system>"."<name>" = derivation;
  # Executed by `nix build .`
  packages."<system>".default = derivation;
  # Executed by `nix run .#<name>`
  apps."<system>"."<name>" = {
    type = "app";
    program = "<store-path>";
  };
  # Executed by `nix run . -- <args?>`
  apps."<system>".default = { type = "app"; program = "..."; };

  # Used for nixpkgs packages, also accessible via `nix build .#<name>`
  legacyPackages."<system>"."<name>" = derivation;
  # Overlay, consumed by other flakes
  overlays."<name>" = final: prev: { };
  # Default overlay
  overlays.default = {};
  # Nixos module, consumed by other flakes
  nixosModules."<name>" = { config }: { options = {}; config = {}; };
  # Default module
  nixosModules.default = {};
  # Used with `nixos-rebuild --flake .#<hostname>`
  # nixosConfigurations."<hostname>".config.system.build.toplevel must be a derivation
  nixosConfigurations."<hostname>" = {};
  # Used by `nix develop .#<name>`
  devShells."<system>"."<name>" = derivation;
  # Used by `nix develop`
  devShells."<system>".default = derivation;
  # Hydra build jobs
  hydraJobs."<attr>"."<system>" = derivation;
  # Used by `nix flake init -t <flake>#<name>`
  templates."<name>" = {
    path = "<store-path>";
    description = "template description goes here?";
  };
  # Used by `nix flake init -t <flake>`
  templates.default = { path = "<store-path>"; description = ""; };
}
```

The most common outputs we use in the RV flakes are:

* `packages."<system>".<our_package_name>`, this should be a derivation building the `<our_package_name>`, which we then build with the command `nix build .#<our_package_name>`
* `packages."<system>".default`/ `defaultPackage."<system>"`, which we then build with the command `nix build .`
* `devShells."<system>".default` this should be a derivavtion for a nix shell with all the dependencies needed to manually build the current project. You can drop into the shell via `nix develop .`
* `devShells."<system>".<dev_shell_name>` in case we need multiple dev shells, you can drop into the spcific one via `nix develop .#<dev_shell_name>`
* `overlays.default` / `overlays."<name>"` - An overlay which adds out package to nixpkgs. See below for what overlays are.

## Nix overlays

> Overlays are Nix functions which accept two arguments, conventionally called self and super, and return a set of packages.

(These days `self` has been renamed `final` and `super` to `prev`)

How is this useful? We usually base all our derivations on `nixpkg` because it contains most of the build tools and convenience functions that we want to use for building our derivation. However, when we want to compose different projects that depend on each other, it can be cumbersome to build stuff in such as way that project 1 doesn't depend on a different version of nixpkgs from project 2. Overlays help with this by providing a recipe for building our project abstractly, without depending on a specific `nixpkgs`.  We can then compose several such abstract recipes to get a custom nixpkgs with our packages added. 

Let's see an example. Assume we have a nix expression building `foo`:

```nix
let pkgs = import <nixpkgs> {};
in {
  foo = pkgs.stdenv.mkDerivation ...
}
```

If we now want to build `bar` in another flake that depends on `foo`, we write

```nix
let 
  pkgs = import <nixpkgs> {};
  foo = import <path_to_foo>;
in {
  bar = pkgs.stdenv.mkDerivation {
    buildInputs = [ foo ];
    ...
  }
}
```

However, the version of `nixpkgs` that was used to build `foo` may be different from the one used for `bar`, which can often mean we have to download multiple versions of tools which might otherwise have been shared. What we can do instead is to refactor both `foo` and `bar` into two overlays:

```nix
let overlay-foo = final: prev: {
  foo = prev.stdenv.mkDerivation ...
}
```

and

```nix
let overlay-bar = final: prev: {
  bar = pkgs.stdenv.mkDerivation {
    buildInputs = [ prev.foo ];
    ...
  }
}
```

Now we can import a single version of nixpkgs with the two overlays applied:

```nix
let pkgs = import <nixpkgs> { overlays = [ overlay-foo overlay-bar ]; };
in {
  foo = pkgs.foo;
  bar = pkgs.bar;
}
```

In the diagram below, `main` is the original `<nixpkgs>` and `ext-1`, `ext-2` correspond to the overlays `overlay-foo`, `overlay-bar`:

![](https://nixos.wiki/images/1/1a/Dram-overlay-self-super.png)


Overlays are also useful when we want to override an existing package in nixpkgs, e.g. the version of Z3 we want to use in [haskell-backend](https://github.com/runtimeverification/haskell-backend/blob/859a75aa85ec41c2c6c87c5074d12bc4ad2dd2b8/flake.nix#L112-L122):

```nix
inputs = {
  z3-src = {
    url = "github:Z3Prover/z3/z3-4.8.15";
    flake = false;
  };
};
outputs = {
  ...
  overlay = final: prev: {
    z3 = prev.z3.overrideAttrs (old: {
      src = z3-src;
    });
  }
}
```

The above nix code allows us to precisely specify the z3 version we want to use, instead of relying on whichever version is currently available in the pinned `nixpkgs` version our flake uses.

# Python nix infrastructure

We use [poetry2nix](https://github.com/nix-community/poetry2nix) for all pyk/python based projects at RV. The skeleton structure of a python project based on pyk will look something like this:

```nix
{
  description = "kfoo - K tooling for the Bar platform";

  inputs = {
    k-framework.url = "github:runtimeverification/k-framework/v...";
    nixpkgs.follows = "k-framework/nixpkgs";
    flake-utils.follows = "k-framework/flake-utils";
    rv-utils.follows = "k-framework/rv-utils";
    poetry2nix.follows = "k-framework/poetry2nix";
  };

  outputs = { self, k-framework, nixpkgs, flake-utils, rv-utils, ... }@inputs:
    let
      overlay = (final: prev:
        let
          poetry2nix = inputs.poetry2nix.lib.mkPoetry2Nix { pkgs = prev; };
        in rec {
          kfoo = prev.stdenv.mkDerivation {
            pname = "kfoo";
            src = ./.;
            version = "0.0.1";

            buildInputs = with final; [
              k-framework.packages.${system}.k
              kfoo-pyk
            ];

            dontUseCmakeConfigure = true;

            nativeBuildInputs = [ prev.makeWrapper ];

            enableParallelBuilding = true;

            buildPhase = ''
              export XDG_CACHE_HOME=$(pwd)
              ${
                prev.lib.optionalString
                (prev.stdenv.isAarch64 && prev.stdenv.isDarwin)
                "APPLE_SILICON=true"
              } K_OPTS="-Xmx8G -Xss512m" kdist -v build foo-semantics.* -j$NIX_BUILD_CORES
            '';

            installPhase = ''
              mkdir -p $out
              cp -r ./kdist-*/* $out/

              makeWrapper ${komet-pyk}/bin/kfoo $out/bin/kfoo --prefix PATH : ${
                prev.lib.makeBinPath [ k-framework.packages.${prev.system}.k ]
              } --set KDIST_DIR $out
            '';
          };

          kfoo-pyk = poetry2nix.mkPoetryApplication {
            python = prev.python310;
            projectDir = ./kfoo;
            src = rv-utils.lib.mkSubdirectoryAppSrc {
              pkgs = prev;
              src = ./.;
              subdirectories = [ "kfoo" ];
              cleaner = poetry2nix.cleanPythonSources;
            };
            overrides = poetry2nix.overrides.withDefaults
              (finalPython: prevPython: {
                kframework = k-framework.packages.${prev.system}.pyk-python310;
              });
            groups = [ ];
            checkGroups = [ ];
          };
        });
    in flake-utils.lib.eachSystem [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-linux"
      "aarch64-darwin"
    ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ overlay ];
        };
      in {
        packages = rec {
          inherit (pkgs) kfoo kfoo-pyk;
          default = pkgs.kfoo;
        };
      }) // {
        overlays.default = overlay;
      };
}
```

Things to note in the above skeleton structure:

* We want to make sure that any common libraries flow from the upstream dependencies, e.g `nixpkgs`, `rv-utils` and `poetry2nix` are inherited from the `k-framework` flake. This ensures we are always in lockstep with `k-framework` when using these libraries. This would transitively apply if we depend on a project `foo` which itself depends on `k-framework`. By first depending on `foo` and then setting `k-framework.follows = foo/k-framework`, we avoid the need to manually set the `k-framework` version as well as the version of `foo`.

* The way to import `poetry2nix` has changed (semi)recently. It used to be that `poetry2nix` was added as an overlay to `nixpkgs` and could be referenced via `pkgs.poetry2nix` or if defining a package via an overlay, such as the one above, we could use `final.poetry2nix`. Now, we import an instance of the poetry2nix library via `inputs.poetry2nix.lib.mkPoetry2Nix { pkgs = prev; };`

* The template above assumes we have a pyk based package `foo` together with some `kdist` targets, i.e. a K definition of the semantics. We build the final package `foo` by first bundling the python code into the package `foo-pyk` and then building `foo` by running `kdist`
  ```nix
  buildPhase = ''
    export XDG_CACHE_HOME=$(pwd)
    ${
      prev.lib.optionalString
      (prev.stdenv.isAarch64 && prev.stdenv.isDarwin)
      "APPLE_SILICON=true"
    } K_OPTS="-Xmx8G -Xss512m" kdist -v build foo-semantics.* -j$NIX_BUILD_CORES
  '';
  ```
  and wrapping `foo-pyk`'s executable with the path to K, as well as any other runtime dependencies that `foo` might have using the [makeWrapper](https://gist.github.com/CMCDragonkai/9b65cbb1989913555c203f4fa9c23374) utility
  ```nix
  installPhase = ''
    mkdir -p $out
    cp -r ./kdist-*/* $out/

    makeWrapper ${komet-pyk}/bin/kfoo $out/bin/kfoo --prefix PATH : ${
      prev.lib.makeBinPath [ k-framework.packages.${prev.system}.k ]
    } --set KDIST_DIR $out
  '';
  ```
  Notice we also set the `KDIST_DIR` env variable to the path of the package we are currently building (`$out`), where we previously copied the results of running `kdist` in the `buildPhase`. This has been set up so that `foo` looks for the compiled semantics inside the `nix` store, rather than the user's local `kdist` folder in `~`. This ensures that `foo` will be self-contained when we want to e.g. download it from the nix binary cache via `kup`.

* When building a python package via poetry2nix, we will often need to make tweaks to the nix derivations of the dependencies for said package. We usually do this for one of two reasons. The first reason is when we want to manually override an upstream dependency, such as the `pyk` (now renamed to `kframework`) package. This has been done in the code above:
  ```nix
  overrides = poetry2nix.overrides.withDefaults
    (finalPython: prevPython: {
      kframework = k-framework.packages.${prev.system}.pyk-python310;
    });
  ```
  Here, we set the `kframework` python package (i.e. `pyk`) to be pulled directly from the `k-framework` flake (see here for where the `kframework` python package is built in the K repo: https://github.com/runtimeverification/k/blob/ddc22368b132914e64811f507c87725d1b96dc4d/nix/pyk-overlay.nix#L4-L25). This has two potential advantages, namely we get some better caching because the pyk package is put into the cachix cache so we avoid a bit of work, but we also get a better assurance that the version of pyk we assume in the `poetry.lock` file corresponds to the version found in the `k-framework` flake that we specified in the inputs. If there is a mismatch, this indicates that the nix flake is not correctly synced to `pyproject.toml`.   
  Another reason we may need to add overrides is described in the troubleshooting section under the **poetry2nix: ModuleNotFoundError** heading.



# Java/Maven nix infrastructure

We use a modified version of the [buildMavenPackage](https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/maven.section.md#building-a-package-using-mavenbuildmavenpackage-maven-buildmavenpackage) infrastructure provided by nixpkgs. To see the differences, compare the [RV version](https://github.com/runtimeverification/k/blob/ddc22368b132914e64811f507c87725d1b96dc4d/nix/build-maven-package.nix) vs the [nixpkgs version](https://github.com/NixOS/nixpkgs/blob/69493a13eaea0dc4682fd07e8a084f17813dbeeb/pkgs/development/tools/build-managers/apache-maven/build-package.nix). Both versions use a maven plugin to download dependencies for a project and store them in the nix store. Then, when building the final package, maven is called in offline mode, using the pre-downloaded packages. The version committed in the K repo has been carefully tweaked to work around the poorly maintained `org.apache.maven.plugins:maven-dependency-plugin` plugin, namely, the plugin does not always download the full dependency set for some reason and will occasionally fail, in which case we have to manually instruct nix to download that particular package manually. See the troubleshooting section for details.

To package the nix version of K, we have quite a complex nix derivation, maintained here: https://github.com/runtimeverification/k/blob/master/nix/k.nix

The process of building K in nix invloves the following steps:


1) Call maven skipping tests as well as building the llvm and haskell backends:
    ```nix
    mvnParameters =
      "-DskipTests -DskipKTest=true -Dllvm.backend.skip=true -Dhaskell.backend.skip=true -DsecondaryCacheDir=secondary-cache";
    ```

2) We do not want to have maven build the two backends because we delegate this to nix instead. Hence, we have to copy or symlink the correct build outputs from both backends to where [K expects them](https://github.com/runtimeverification/k/blob/ddc22368b132914e64811f507c87725d1b96dc4d/nix/k.nix#L61-L80).

3) K uses clang/LLVM both as a build time and runtime dependency. Due to the packaging of LLVM/clang in nix, the `clang` binary is sanitised to not look into any local folders for libraries/headers/etc. As a result, we provide a special env variable `NIX_LLVM_KOMPILE_LIBS`, which can be used to explicitly point `clang` or more specifically, `llvm-kompile` to any libraries that we may want to use. This is necessary for building the blockchain-plugin, which requires libraries such as `openssl` or `secp256k1`. Indeed, when we build the nix target `k.openssl.secp256k1`, we are essentially just wrapping all the K binaries such as `kompile` with paths to the two libraries, passed via the `NIX_LLVM_KOMPILE_LIBS` variable using the aforementioned `makeWrapper`/`wrapProgram` nix utility.

4) We additionally set the `PATH` for all the K binaries such as `kompile` using `makeWrapper`, adding any runtime dependencies these tools might have, such as `bison`, `z3`, `java`, etc. This again ensures that a `nix`/`kup` installed version of K always uses the same Java/Z3/Bison/etc version, hopefully avoiding strange bugs, which can easily crop up due to runtime dependency incompatibilities between different systems.




# Haskell nix infrastructure

The Haskell backend uses the [stacklock2nix](https://github.com/cdepillabout/stacklock2nix) library for building the booster and kore packages. The haskell-backend flake also exports the canonical version of z3, used in all the downstream dependencies, as Z3 can have wildly different performance characteristics between versions.


# Troubleshooting

## Flake follows non-existent input

```
error:
       … while updating the lock file of flake ...

       error: input 'flake-utils' follows a non-existent input 'k-framework/flake-utils'
```

This is most likely caused by an old version of nix. Has been observed on nix 2.13 and should not be present on >2.18.


## Poetry2nix: ModuleNotFoundError

```
error: builder for '/nix/store/7d4hzmmcwg4dkava31q36bxpg8gik4c1-python3.9-foo-1.2.3.drv' failed with exit code 2;
       last 10 log lines:
       ...
       >   File "<frozen importlib._bootstrap>", line 984, in _find_and_load_unlocked
       > ModuleNotFoundError: No module named 'bar'
```

The above error can occur when building our python package `foo` via poetry2nix. The error indicates that the python package `bar` that `foo` depends on failed to build, due to a missing dependency `bar` has on `baz`. We need to manually fix the imports of the `bar` python package, by including the package `baz` in its dependencies/build inputs:

```nix
foo = poetry2nix.mkPoetryApplication {
  ...
  overrides = poetry2nix.overrides.withDefaults
    (finalPython: prevPython: {
      bar = prevPython.bar.overridePythonAttrs (old: {
        propagatedBuildInputs = (old.propagatedBuildInputs or [ ])
          ++ [ finalPython.baz ];
      });
    });
  ...
};
```

## Maven build failure

When building K (or any other maven project), a common error that can occur will look something like this
```
[ERROR] Failed to execute goal ... org.apache.maven.artifact.resolver.ArtifactNotFoundException: The following artifacts could not be resolved: org.scala-lang:scala-compiler:jar:2.12.18 ...`
```

In this case, we have to manually instruct nix to download the package by adding `"org.scala-lang:scala-compiler:2.12.18"` (without the `jar:`) to `manualMvnArtifacts` list in `flake.nix` (if that doesn't work, try the `manualMvnSourceArtifacts` instead). When this happens, or whenever we change the Java dependencies by e.g. updating a package version, the nix build will fail with the following error:

```bash
error: hash mismatch in fixed-output derivation '/nix/store/wjz7gjqs3cch9lgdjhs1fnb8wfl352vd-k-6.1.0-dirty-maven-deps.drv':
        specified: sha256-kLpjMj05uC94/5vGMwMlFzLKNFOKey◊Nvq/vmB6pHTAo=
              got: sha256-fFlRqlLDZnVuoJniPvXjqdYEjnKxmFCEniavau/1gcQ=
error: 1 dependencies of derivation '/nix/store/79hazjbxp8829wpjvhh9c7kzc1m0ii22-k-6.1.0-dirty.drv' failed to build
```

Copy the hash (`sha256-fFlRqlLDZnVuoJniPvXjqdYEjnKxmFCEniavau/1gcQ=`) and replace it in `flake.nix`:

```nix
k-framework = { haskell-backend-bins, llvm-kompile-libs }:
    prev.callPackage ./nix/k.nix {
        mvnHash = "sha256-fFlRqlLDZnVuoJniPvXjqdYEjnKxmFCEniavau/1gcQ=";
        ...
```
