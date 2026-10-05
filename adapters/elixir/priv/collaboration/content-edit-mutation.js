var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __commonJS = (cb, mod) => function __require() {
  return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key2 of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key2) && key2 !== except)
        __defProp(to, key2, { get: () => from[key2], enumerable: !(desc = __getOwnPropDesc(from, key2)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));

// node_modules/core-js-pure/modules/es.error.to-string.js
var require_es_error_to_string = __commonJS({
  "node_modules/core-js-pure/modules/es.error.to-string.js"() {
  }
});

// node_modules/core-js-pure/modules/es.object.to-string.js
var require_es_object_to_string = __commonJS({
  "node_modules/core-js-pure/modules/es.object.to-string.js"() {
  }
});

// node_modules/core-js-pure/internals/global-this.js
var require_global_this = __commonJS({
  "node_modules/core-js-pure/internals/global-this.js"(exports, module) {
    "use strict";
    var check = function(it) {
      return it && it.Math === Math && it;
    };
    module.exports = // eslint-disable-next-line es/no-global-this -- safe
    check(typeof globalThis == "object" && globalThis) || check(typeof window == "object" && window) || // eslint-disable-next-line no-restricted-globals -- safe
    check(typeof self == "object" && self) || check(typeof global == "object" && global) || check(typeof exports == "object" && exports) || // eslint-disable-next-line no-new-func -- fallback
    /* @__PURE__ */ (function() {
      return this;
    })() || Function("return this")();
  }
});

// node_modules/core-js-pure/internals/fails.js
var require_fails = __commonJS({
  "node_modules/core-js-pure/internals/fails.js"(exports, module) {
    "use strict";
    module.exports = function(exec) {
      try {
        return !!exec();
      } catch (error) {
        return true;
      }
    };
  }
});

// node_modules/core-js-pure/internals/function-bind-native.js
var require_function_bind_native = __commonJS({
  "node_modules/core-js-pure/internals/function-bind-native.js"(exports, module) {
    "use strict";
    var fails = require_fails();
    module.exports = !fails(function() {
      var test = function() {
      }.bind();
      return typeof test != "function" || test.hasOwnProperty("prototype");
    });
  }
});

// node_modules/core-js-pure/internals/function-apply.js
var require_function_apply = __commonJS({
  "node_modules/core-js-pure/internals/function-apply.js"(exports, module) {
    "use strict";
    var NATIVE_BIND = require_function_bind_native();
    var FunctionPrototype = Function.prototype;
    var apply = FunctionPrototype.apply;
    var call = FunctionPrototype.call;
    module.exports = typeof Reflect == "object" && Reflect.apply || (NATIVE_BIND ? call.bind(apply) : function() {
      return call.apply(apply, arguments);
    });
  }
});

// node_modules/core-js-pure/internals/function-uncurry-this.js
var require_function_uncurry_this = __commonJS({
  "node_modules/core-js-pure/internals/function-uncurry-this.js"(exports, module) {
    "use strict";
    var NATIVE_BIND = require_function_bind_native();
    var FunctionPrototype = Function.prototype;
    var call = FunctionPrototype.call;
    var uncurryThisWithBind = NATIVE_BIND && FunctionPrototype.bind.bind(call, call);
    module.exports = NATIVE_BIND ? uncurryThisWithBind : function(fn) {
      return function() {
        return call.apply(fn, arguments);
      };
    };
  }
});

// node_modules/core-js-pure/internals/classof-raw.js
var require_classof_raw = __commonJS({
  "node_modules/core-js-pure/internals/classof-raw.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this();
    var toString = uncurryThis({}.toString);
    var stringSlice = uncurryThis("".slice);
    module.exports = function(it) {
      return stringSlice(toString(it), 8, -1);
    };
  }
});

// node_modules/core-js-pure/internals/function-uncurry-this-clause.js
var require_function_uncurry_this_clause = __commonJS({
  "node_modules/core-js-pure/internals/function-uncurry-this-clause.js"(exports, module) {
    "use strict";
    var classofRaw = require_classof_raw();
    var uncurryThis = require_function_uncurry_this();
    module.exports = function(fn) {
      if (classofRaw(fn) === "Function") return uncurryThis(fn);
    };
  }
});

// node_modules/core-js-pure/internals/is-callable.js
var require_is_callable = __commonJS({
  "node_modules/core-js-pure/internals/is-callable.js"(exports, module) {
    "use strict";
    var documentAll = typeof document == "object" && document.all;
    module.exports = typeof documentAll == "undefined" && documentAll !== void 0 ? function(argument) {
      return typeof argument == "function" || argument === documentAll;
    } : function(argument) {
      return typeof argument == "function";
    };
  }
});

// node_modules/core-js-pure/internals/descriptors.js
var require_descriptors = __commonJS({
  "node_modules/core-js-pure/internals/descriptors.js"(exports, module) {
    "use strict";
    var fails = require_fails();
    module.exports = !fails(function() {
      return Object.defineProperty({}, 1, { get: function() {
        return 7;
      } })[1] !== 7;
    });
  }
});

// node_modules/core-js-pure/internals/function-call.js
var require_function_call = __commonJS({
  "node_modules/core-js-pure/internals/function-call.js"(exports, module) {
    "use strict";
    var NATIVE_BIND = require_function_bind_native();
    var call = Function.prototype.call;
    module.exports = NATIVE_BIND ? call.bind(call) : function() {
      return call.apply(call, arguments);
    };
  }
});

// node_modules/core-js-pure/internals/object-property-is-enumerable.js
var require_object_property_is_enumerable = __commonJS({
  "node_modules/core-js-pure/internals/object-property-is-enumerable.js"(exports) {
    "use strict";
    var $propertyIsEnumerable = {}.propertyIsEnumerable;
    var getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
    var NASHORN_BUG = getOwnPropertyDescriptor && !$propertyIsEnumerable.call({ 1: 2 }, 1);
    exports.f = NASHORN_BUG ? function propertyIsEnumerable(V) {
      var descriptor = getOwnPropertyDescriptor(this, V);
      return !!descriptor && descriptor.enumerable;
    } : $propertyIsEnumerable;
  }
});

// node_modules/core-js-pure/internals/create-property-descriptor.js
var require_create_property_descriptor = __commonJS({
  "node_modules/core-js-pure/internals/create-property-descriptor.js"(exports, module) {
    "use strict";
    module.exports = function(bitmap, value) {
      return {
        enumerable: !(bitmap & 1),
        configurable: !(bitmap & 2),
        writable: !(bitmap & 4),
        value
      };
    };
  }
});

// node_modules/core-js-pure/internals/indexed-object.js
var require_indexed_object = __commonJS({
  "node_modules/core-js-pure/internals/indexed-object.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this();
    var fails = require_fails();
    var classof = require_classof_raw();
    var $Object = Object;
    var split = uncurryThis("".split);
    module.exports = fails(function() {
      return !$Object("z").propertyIsEnumerable(0);
    }) ? function(it) {
      return classof(it) === "String" ? split(it, "") : $Object(it);
    } : $Object;
  }
});

// node_modules/core-js-pure/internals/is-null-or-undefined.js
var require_is_null_or_undefined = __commonJS({
  "node_modules/core-js-pure/internals/is-null-or-undefined.js"(exports, module) {
    "use strict";
    module.exports = function(it) {
      return it === null || it === void 0;
    };
  }
});

// node_modules/core-js-pure/internals/require-object-coercible.js
var require_require_object_coercible = __commonJS({
  "node_modules/core-js-pure/internals/require-object-coercible.js"(exports, module) {
    "use strict";
    var isNullOrUndefined = require_is_null_or_undefined();
    var $TypeError = TypeError;
    module.exports = function(it) {
      if (isNullOrUndefined(it)) throw new $TypeError("Can't call method on " + it);
      return it;
    };
  }
});

// node_modules/core-js-pure/internals/to-indexed-object.js
var require_to_indexed_object = __commonJS({
  "node_modules/core-js-pure/internals/to-indexed-object.js"(exports, module) {
    "use strict";
    var IndexedObject = require_indexed_object();
    var requireObjectCoercible = require_require_object_coercible();
    module.exports = function(it) {
      return IndexedObject(requireObjectCoercible(it));
    };
  }
});

// node_modules/core-js-pure/internals/is-object.js
var require_is_object = __commonJS({
  "node_modules/core-js-pure/internals/is-object.js"(exports, module) {
    "use strict";
    var isCallable = require_is_callable();
    module.exports = function(it) {
      return typeof it == "object" ? it !== null : isCallable(it);
    };
  }
});

// node_modules/core-js-pure/internals/path.js
var require_path = __commonJS({
  "node_modules/core-js-pure/internals/path.js"(exports, module) {
    "use strict";
    module.exports = {};
  }
});

// node_modules/core-js-pure/internals/get-built-in.js
var require_get_built_in = __commonJS({
  "node_modules/core-js-pure/internals/get-built-in.js"(exports, module) {
    "use strict";
    var path = require_path();
    var globalThis2 = require_global_this();
    var isCallable = require_is_callable();
    var aFunction = function(variable) {
      return isCallable(variable) ? variable : void 0;
    };
    module.exports = function(namespace, method) {
      return arguments.length < 2 ? aFunction(path[namespace]) || aFunction(globalThis2[namespace]) : path[namespace] && path[namespace][method] || globalThis2[namespace] && globalThis2[namespace][method];
    };
  }
});

// node_modules/core-js-pure/internals/object-is-prototype-of.js
var require_object_is_prototype_of = __commonJS({
  "node_modules/core-js-pure/internals/object-is-prototype-of.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this();
    module.exports = uncurryThis({}.isPrototypeOf);
  }
});

// node_modules/core-js-pure/internals/environment-user-agent.js
var require_environment_user_agent = __commonJS({
  "node_modules/core-js-pure/internals/environment-user-agent.js"(exports, module) {
    "use strict";
    var globalThis2 = require_global_this();
    var navigator = globalThis2.navigator;
    var userAgent = navigator && navigator.userAgent;
    module.exports = userAgent ? String(userAgent) : "";
  }
});

// node_modules/core-js-pure/internals/environment-v8-version.js
var require_environment_v8_version = __commonJS({
  "node_modules/core-js-pure/internals/environment-v8-version.js"(exports, module) {
    "use strict";
    var globalThis2 = require_global_this();
    var userAgent = require_environment_user_agent();
    var process = globalThis2.process;
    var Deno2 = globalThis2.Deno;
    var versions = process && process.versions || Deno2 && Deno2.version;
    var v8 = versions && versions.v8;
    var match;
    var version;
    if (v8) {
      match = v8.split(".");
      version = match[0] > 0 && match[0] < 4 ? 1 : +(match[0] + match[1]);
    }
    if (!version && userAgent) {
      match = userAgent.match(/Edge\/(\d+)/);
      if (!match || match[1] >= 74) {
        match = userAgent.match(/Chrome\/(\d+)/);
        if (match) version = +match[1];
      }
    }
    module.exports = version;
  }
});

// node_modules/core-js-pure/internals/symbol-constructor-detection.js
var require_symbol_constructor_detection = __commonJS({
  "node_modules/core-js-pure/internals/symbol-constructor-detection.js"(exports, module) {
    "use strict";
    var V8_VERSION = require_environment_v8_version();
    var fails = require_fails();
    var globalThis2 = require_global_this();
    var $String = globalThis2.String;
    module.exports = !!Object.getOwnPropertySymbols && !fails(function() {
      var symbol = Symbol("symbol detection");
      return !$String(symbol) || !(Object(symbol) instanceof Symbol) || // Chrome 38-40 symbols are not inherited from DOM collections prototypes to instances
      !Symbol.sham && V8_VERSION && V8_VERSION < 41;
    });
  }
});

// node_modules/core-js-pure/internals/use-symbol-as-uid.js
var require_use_symbol_as_uid = __commonJS({
  "node_modules/core-js-pure/internals/use-symbol-as-uid.js"(exports, module) {
    "use strict";
    var NATIVE_SYMBOL = require_symbol_constructor_detection();
    module.exports = NATIVE_SYMBOL && !Symbol.sham && typeof Symbol.iterator == "symbol";
  }
});

// node_modules/core-js-pure/internals/is-symbol.js
var require_is_symbol = __commonJS({
  "node_modules/core-js-pure/internals/is-symbol.js"(exports, module) {
    "use strict";
    var getBuiltIn = require_get_built_in();
    var isCallable = require_is_callable();
    var isPrototypeOf = require_object_is_prototype_of();
    var USE_SYMBOL_AS_UID = require_use_symbol_as_uid();
    var $Object = Object;
    module.exports = USE_SYMBOL_AS_UID ? function(it) {
      return typeof it == "symbol";
    } : function(it) {
      var $Symbol = getBuiltIn("Symbol");
      return isCallable($Symbol) && isPrototypeOf($Symbol.prototype, $Object(it));
    };
  }
});

// node_modules/core-js-pure/internals/try-to-string.js
var require_try_to_string = __commonJS({
  "node_modules/core-js-pure/internals/try-to-string.js"(exports, module) {
    "use strict";
    var $String = String;
    module.exports = function(argument) {
      try {
        return $String(argument);
      } catch (error) {
        return "Object";
      }
    };
  }
});

// node_modules/core-js-pure/internals/a-callable.js
var require_a_callable = __commonJS({
  "node_modules/core-js-pure/internals/a-callable.js"(exports, module) {
    "use strict";
    var isCallable = require_is_callable();
    var tryToString = require_try_to_string();
    var $TypeError = TypeError;
    module.exports = function(argument) {
      if (isCallable(argument)) return argument;
      throw new $TypeError(tryToString(argument) + " is not a function");
    };
  }
});

// node_modules/core-js-pure/internals/get-method.js
var require_get_method = __commonJS({
  "node_modules/core-js-pure/internals/get-method.js"(exports, module) {
    "use strict";
    var aCallable = require_a_callable();
    var isNullOrUndefined = require_is_null_or_undefined();
    module.exports = function(V, P) {
      var func = V[P];
      return isNullOrUndefined(func) ? void 0 : aCallable(func);
    };
  }
});

// node_modules/core-js-pure/internals/ordinary-to-primitive.js
var require_ordinary_to_primitive = __commonJS({
  "node_modules/core-js-pure/internals/ordinary-to-primitive.js"(exports, module) {
    "use strict";
    var call = require_function_call();
    var isCallable = require_is_callable();
    var isObject = require_is_object();
    var $TypeError = TypeError;
    module.exports = function(input, pref) {
      var fn, val;
      if (pref === "string" && isCallable(fn = input.toString) && !isObject(val = call(fn, input))) return val;
      if (isCallable(fn = input.valueOf) && !isObject(val = call(fn, input))) return val;
      if (pref !== "string" && isCallable(fn = input.toString) && !isObject(val = call(fn, input))) return val;
      throw new $TypeError("Can't convert object to primitive value");
    };
  }
});

// node_modules/core-js-pure/internals/is-pure.js
var require_is_pure = __commonJS({
  "node_modules/core-js-pure/internals/is-pure.js"(exports, module) {
    "use strict";
    module.exports = true;
  }
});

// node_modules/core-js-pure/internals/define-global-property.js
var require_define_global_property = __commonJS({
  "node_modules/core-js-pure/internals/define-global-property.js"(exports, module) {
    "use strict";
    var globalThis2 = require_global_this();
    var defineProperty = Object.defineProperty;
    module.exports = function(key2, value) {
      try {
        defineProperty(globalThis2, key2, { value, configurable: true, writable: true });
      } catch (error) {
        globalThis2[key2] = value;
      }
      return value;
    };
  }
});

// node_modules/core-js-pure/internals/shared-store.js
var require_shared_store = __commonJS({
  "node_modules/core-js-pure/internals/shared-store.js"(exports, module) {
    "use strict";
    var IS_PURE = require_is_pure();
    var globalThis2 = require_global_this();
    var defineGlobalProperty = require_define_global_property();
    var SHARED = "__core-js_shared__";
    var store = module.exports = globalThis2[SHARED] || defineGlobalProperty(SHARED, {});
    (store.versions || (store.versions = [])).push({
      version: "3.50.0",
      mode: IS_PURE ? "pure" : "global",
      copyright: "\xA9 2013\u20132025 Denis Pushkarev (zloirock.ru), 2025\u20132026 CoreJS Company (core-js.io). All rights reserved.",
      license: "https://github.com/zloirock/core-js/blob/v3.50.0/LICENSE",
      source: "https://github.com/zloirock/core-js"
    });
  }
});

// node_modules/core-js-pure/internals/shared.js
var require_shared = __commonJS({
  "node_modules/core-js-pure/internals/shared.js"(exports, module) {
    "use strict";
    var store = require_shared_store();
    var create = Object.create || Object;
    module.exports = function(key2, value) {
      return store[key2] || (store[key2] = value || create(null));
    };
  }
});

// node_modules/core-js-pure/internals/to-object.js
var require_to_object = __commonJS({
  "node_modules/core-js-pure/internals/to-object.js"(exports, module) {
    "use strict";
    var requireObjectCoercible = require_require_object_coercible();
    var $Object = Object;
    module.exports = function(argument) {
      return $Object(requireObjectCoercible(argument));
    };
  }
});

// node_modules/core-js-pure/internals/has-own-property.js
var require_has_own_property = __commonJS({
  "node_modules/core-js-pure/internals/has-own-property.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this();
    var toObject = require_to_object();
    var hasOwnProperty = uncurryThis({}.hasOwnProperty);
    module.exports = Object.hasOwn || function hasOwn(it, key2) {
      return hasOwnProperty(toObject(it), key2);
    };
  }
});

// node_modules/core-js-pure/internals/uid.js
var require_uid = __commonJS({
  "node_modules/core-js-pure/internals/uid.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this();
    var id2 = 0;
    var postfix = Math.random();
    var toString = uncurryThis(1.1.toString);
    module.exports = function(key2) {
      return "Symbol(" + (key2 === void 0 ? "" : key2) + ")_" + toString(++id2 + postfix, 36);
    };
  }
});

// node_modules/core-js-pure/internals/well-known-symbol.js
var require_well_known_symbol = __commonJS({
  "node_modules/core-js-pure/internals/well-known-symbol.js"(exports, module) {
    "use strict";
    var globalThis2 = require_global_this();
    var shared = require_shared();
    var hasOwn = require_has_own_property();
    var uid = require_uid();
    var NATIVE_SYMBOL = require_symbol_constructor_detection();
    var USE_SYMBOL_AS_UID = require_use_symbol_as_uid();
    var Symbol2 = globalThis2.Symbol;
    var WellKnownSymbolsStore = shared("wks");
    var createWellKnownSymbol = USE_SYMBOL_AS_UID ? Symbol2["for"] || Symbol2 : Symbol2 && Symbol2.withoutSetter || uid;
    module.exports = function(name) {
      if (!hasOwn(WellKnownSymbolsStore, name)) {
        WellKnownSymbolsStore[name] = NATIVE_SYMBOL && hasOwn(Symbol2, name) ? Symbol2[name] : createWellKnownSymbol("Symbol." + name);
      }
      return WellKnownSymbolsStore[name];
    };
  }
});

// node_modules/core-js-pure/internals/to-primitive.js
var require_to_primitive = __commonJS({
  "node_modules/core-js-pure/internals/to-primitive.js"(exports, module) {
    "use strict";
    var call = require_function_call();
    var isObject = require_is_object();
    var isSymbol = require_is_symbol();
    var getMethod = require_get_method();
    var ordinaryToPrimitive = require_ordinary_to_primitive();
    var wellKnownSymbol = require_well_known_symbol();
    var $TypeError = TypeError;
    var TO_PRIMITIVE = wellKnownSymbol("toPrimitive");
    module.exports = function(input, pref) {
      if (!isObject(input) || isSymbol(input)) return input;
      var exoticToPrim = getMethod(input, TO_PRIMITIVE);
      var result;
      if (exoticToPrim) {
        if (pref === void 0) pref = "default";
        result = call(exoticToPrim, input, pref);
        if (!isObject(result) || isSymbol(result)) return result;
        throw new $TypeError("Can't convert object to primitive value");
      }
      if (pref === void 0) pref = "number";
      return ordinaryToPrimitive(input, pref);
    };
  }
});

// node_modules/core-js-pure/internals/to-property-key.js
var require_to_property_key = __commonJS({
  "node_modules/core-js-pure/internals/to-property-key.js"(exports, module) {
    "use strict";
    var toPrimitive = require_to_primitive();
    var isSymbol = require_is_symbol();
    module.exports = function(argument) {
      var key2 = toPrimitive(argument, "string");
      return isSymbol(key2) ? key2 : key2 + "";
    };
  }
});

// node_modules/core-js-pure/internals/document-create-element.js
var require_document_create_element = __commonJS({
  "node_modules/core-js-pure/internals/document-create-element.js"(exports, module) {
    "use strict";
    var globalThis2 = require_global_this();
    var isObject = require_is_object();
    var document2 = globalThis2.document;
    var EXISTS = isObject(document2) && isObject(document2.createElement);
    module.exports = function(it) {
      return EXISTS ? document2.createElement(it) : {};
    };
  }
});

// node_modules/core-js-pure/internals/ie8-dom-define.js
var require_ie8_dom_define = __commonJS({
  "node_modules/core-js-pure/internals/ie8-dom-define.js"(exports, module) {
    "use strict";
    var DESCRIPTORS = require_descriptors();
    var fails = require_fails();
    var createElement = require_document_create_element();
    module.exports = !DESCRIPTORS && !fails(function() {
      return Object.defineProperty(createElement("div"), "a", {
        get: function() {
          return 7;
        }
      }).a !== 7;
    });
  }
});

// node_modules/core-js-pure/internals/object-get-own-property-descriptor.js
var require_object_get_own_property_descriptor = __commonJS({
  "node_modules/core-js-pure/internals/object-get-own-property-descriptor.js"(exports) {
    "use strict";
    var DESCRIPTORS = require_descriptors();
    var call = require_function_call();
    var propertyIsEnumerableModule = require_object_property_is_enumerable();
    var createPropertyDescriptor = require_create_property_descriptor();
    var toIndexedObject = require_to_indexed_object();
    var toPropertyKey = require_to_property_key();
    var hasOwn = require_has_own_property();
    var IE8_DOM_DEFINE = require_ie8_dom_define();
    var $getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
    exports.f = DESCRIPTORS ? $getOwnPropertyDescriptor : function getOwnPropertyDescriptor(O, P) {
      O = toIndexedObject(O);
      P = toPropertyKey(P);
      if (IE8_DOM_DEFINE) try {
        return $getOwnPropertyDescriptor(O, P);
      } catch (error) {
      }
      if (hasOwn(O, P)) return createPropertyDescriptor(!call(propertyIsEnumerableModule.f, O, P), O[P]);
    };
  }
});

// node_modules/core-js-pure/internals/is-forced.js
var require_is_forced = __commonJS({
  "node_modules/core-js-pure/internals/is-forced.js"(exports, module) {
    "use strict";
    var fails = require_fails();
    var isCallable = require_is_callable();
    var replacement = /#|\.prototype\./;
    var isForced = function(feature, detection) {
      var value = data[normalize(feature)];
      return value === POLYFILL ? true : value === NATIVE ? false : isCallable(detection) ? fails(detection) : !!detection;
    };
    var normalize = isForced.normalize = function(string) {
      return String(string).replace(replacement, ".").toLowerCase();
    };
    var data = isForced.data = {};
    var NATIVE = isForced.NATIVE = "N";
    var POLYFILL = isForced.POLYFILL = "P";
    module.exports = isForced;
  }
});

// node_modules/core-js-pure/internals/function-bind-context.js
var require_function_bind_context = __commonJS({
  "node_modules/core-js-pure/internals/function-bind-context.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this_clause();
    var aCallable = require_a_callable();
    var NATIVE_BIND = require_function_bind_native();
    var bind = uncurryThis(uncurryThis.bind);
    module.exports = function(fn, that) {
      aCallable(fn);
      return that === void 0 ? fn : NATIVE_BIND ? bind(fn, that) : function() {
        return fn.apply(that, arguments);
      };
    };
  }
});

// node_modules/core-js-pure/internals/v8-prototype-define-bug.js
var require_v8_prototype_define_bug = __commonJS({
  "node_modules/core-js-pure/internals/v8-prototype-define-bug.js"(exports, module) {
    "use strict";
    var DESCRIPTORS = require_descriptors();
    var fails = require_fails();
    module.exports = DESCRIPTORS && fails(function() {
      return Object.defineProperty(function() {
      }, "prototype", {
        value: 42,
        writable: false
      }).prototype !== 42;
    });
  }
});

// node_modules/core-js-pure/internals/an-object.js
var require_an_object = __commonJS({
  "node_modules/core-js-pure/internals/an-object.js"(exports, module) {
    "use strict";
    var isObject = require_is_object();
    var $String = String;
    var $TypeError = TypeError;
    module.exports = function(argument) {
      if (isObject(argument)) return argument;
      throw new $TypeError($String(argument) + " is not an object");
    };
  }
});

// node_modules/core-js-pure/internals/object-define-property.js
var require_object_define_property = __commonJS({
  "node_modules/core-js-pure/internals/object-define-property.js"(exports) {
    "use strict";
    var DESCRIPTORS = require_descriptors();
    var IE8_DOM_DEFINE = require_ie8_dom_define();
    var V8_PROTOTYPE_DEFINE_BUG = require_v8_prototype_define_bug();
    var anObject = require_an_object();
    var toPropertyKey = require_to_property_key();
    var $TypeError = TypeError;
    var $defineProperty = Object.defineProperty;
    var $getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
    var ENUMERABLE = "enumerable";
    var CONFIGURABLE = "configurable";
    var WRITABLE = "writable";
    exports.f = DESCRIPTORS ? V8_PROTOTYPE_DEFINE_BUG ? function defineProperty(O, P, Attributes) {
      anObject(O);
      P = toPropertyKey(P);
      anObject(Attributes);
      if (typeof O === "function" && P === "prototype" && "value" in Attributes && WRITABLE in Attributes && !Attributes[WRITABLE]) {
        var current = $getOwnPropertyDescriptor(O, P);
        if (current && current[WRITABLE]) {
          O[P] = Attributes.value;
          Attributes = {
            configurable: CONFIGURABLE in Attributes ? Attributes[CONFIGURABLE] : current[CONFIGURABLE],
            enumerable: ENUMERABLE in Attributes ? Attributes[ENUMERABLE] : current[ENUMERABLE],
            writable: false
          };
        }
      }
      return $defineProperty(O, P, Attributes);
    } : $defineProperty : function defineProperty(O, P, Attributes) {
      anObject(O);
      P = toPropertyKey(P);
      anObject(Attributes);
      if (IE8_DOM_DEFINE) try {
        return $defineProperty(O, P, Attributes);
      } catch (error) {
      }
      if ("get" in Attributes || "set" in Attributes) throw new $TypeError("Accessors not supported");
      if ("value" in Attributes) O[P] = Attributes.value;
      return O;
    };
  }
});

// node_modules/core-js-pure/internals/create-non-enumerable-property.js
var require_create_non_enumerable_property = __commonJS({
  "node_modules/core-js-pure/internals/create-non-enumerable-property.js"(exports, module) {
    "use strict";
    var DESCRIPTORS = require_descriptors();
    var definePropertyModule = require_object_define_property();
    var createPropertyDescriptor = require_create_property_descriptor();
    module.exports = DESCRIPTORS ? function(object4, key2, value) {
      return definePropertyModule.f(object4, key2, createPropertyDescriptor(1, value));
    } : function(object4, key2, value) {
      object4[key2] = value;
      return object4;
    };
  }
});

// node_modules/core-js-pure/internals/export.js
var require_export = __commonJS({
  "node_modules/core-js-pure/internals/export.js"(exports, module) {
    "use strict";
    var globalThis2 = require_global_this();
    var apply = require_function_apply();
    var uncurryThis = require_function_uncurry_this_clause();
    var isCallable = require_is_callable();
    var getOwnPropertyDescriptor = require_object_get_own_property_descriptor().f;
    var isForced = require_is_forced();
    var path = require_path();
    var bind = require_function_bind_context();
    var createNonEnumerableProperty = require_create_non_enumerable_property();
    var hasOwn = require_has_own_property();
    require_shared_store();
    var wrapConstructor = function(NativeConstructor) {
      var Wrapper = function(a, b, c) {
        if (this instanceof Wrapper) {
          switch (arguments.length) {
            case 0:
              return new NativeConstructor();
            case 1:
              return new NativeConstructor(a);
            case 2:
              return new NativeConstructor(a, b);
          }
          return new NativeConstructor(a, b, c);
        }
        return apply(NativeConstructor, this, arguments);
      };
      Wrapper.prototype = NativeConstructor.prototype;
      return Wrapper;
    };
    module.exports = function(options, source) {
      var TARGET = options.target;
      var GLOBAL = options.global;
      var STATIC = options.stat;
      var PROTO = options.proto;
      var nativeSource = GLOBAL ? globalThis2 : STATIC ? globalThis2[TARGET] : globalThis2[TARGET] && globalThis2[TARGET].prototype;
      var target = GLOBAL ? path : path[TARGET] || createNonEnumerableProperty(path, TARGET, {})[TARGET];
      var targetPrototype = target.prototype;
      var FORCED, USE_NATIVE, VIRTUAL_PROTOTYPE;
      var key2, sourceProperty, targetProperty, nativeProperty, resultProperty, descriptor;
      for (key2 in source) {
        FORCED = isForced(GLOBAL ? key2 : TARGET + (STATIC ? "." : "#") + key2, options.forced);
        USE_NATIVE = !FORCED && nativeSource && hasOwn(nativeSource, key2);
        targetProperty = target[key2];
        if (USE_NATIVE) if (options.dontCallGetSet) {
          descriptor = getOwnPropertyDescriptor(nativeSource, key2);
          nativeProperty = descriptor && descriptor.value;
        } else nativeProperty = nativeSource[key2];
        sourceProperty = USE_NATIVE && nativeProperty ? nativeProperty : source[key2];
        if (!FORCED && !PROTO && typeof targetProperty == typeof sourceProperty) continue;
        if (options.bind && USE_NATIVE) resultProperty = bind(sourceProperty, globalThis2);
        else if (options.wrap && USE_NATIVE) resultProperty = wrapConstructor(sourceProperty);
        else if (PROTO && isCallable(sourceProperty)) resultProperty = uncurryThis(sourceProperty);
        else resultProperty = sourceProperty;
        if (options.sham || sourceProperty && sourceProperty.sham || targetProperty && targetProperty.sham) {
          createNonEnumerableProperty(resultProperty, "sham", true);
        }
        createNonEnumerableProperty(target, key2, resultProperty);
        if (PROTO) {
          VIRTUAL_PROTOTYPE = TARGET + "Prototype";
          if (!hasOwn(path, VIRTUAL_PROTOTYPE)) {
            createNonEnumerableProperty(path, VIRTUAL_PROTOTYPE, {});
          }
          createNonEnumerableProperty(path[VIRTUAL_PROTOTYPE], key2, sourceProperty);
          if (options.real && targetPrototype && (FORCED || !targetPrototype[key2])) {
            createNonEnumerableProperty(targetPrototype, key2, sourceProperty);
          }
        }
      }
    };
  }
});

// node_modules/core-js-pure/internals/to-string-tag-support.js
var require_to_string_tag_support = __commonJS({
  "node_modules/core-js-pure/internals/to-string-tag-support.js"(exports, module) {
    "use strict";
    var wellKnownSymbol = require_well_known_symbol();
    var TO_STRING_TAG = wellKnownSymbol("toStringTag");
    var test = {};
    test[TO_STRING_TAG] = "z";
    module.exports = String(test) === "[object z]";
  }
});

// node_modules/core-js-pure/internals/classof.js
var require_classof = __commonJS({
  "node_modules/core-js-pure/internals/classof.js"(exports, module) {
    "use strict";
    var TO_STRING_TAG_SUPPORT = require_to_string_tag_support();
    var isCallable = require_is_callable();
    var classofRaw = require_classof_raw();
    var wellKnownSymbol = require_well_known_symbol();
    var TO_STRING_TAG = wellKnownSymbol("toStringTag");
    var $Object = Object;
    var CORRECT_ARGUMENTS = classofRaw(/* @__PURE__ */ (function() {
      return arguments;
    })()) === "Arguments";
    var tryGet = function(it, key2) {
      try {
        return it[key2];
      } catch (error) {
      }
    };
    module.exports = TO_STRING_TAG_SUPPORT ? classofRaw : function(it) {
      var O, tag, result;
      return it === void 0 ? "Undefined" : it === null ? "Null" : typeof (tag = tryGet(O = $Object(it), TO_STRING_TAG)) == "string" ? tag : CORRECT_ARGUMENTS ? classofRaw(O) : (result = classofRaw(O)) === "Object" && isCallable(O.callee) ? "Arguments" : result;
    };
  }
});

// node_modules/core-js-pure/internals/to-string.js
var require_to_string = __commonJS({
  "node_modules/core-js-pure/internals/to-string.js"(exports, module) {
    "use strict";
    var classof = require_classof();
    var $String = String;
    module.exports = function(argument) {
      if (classof(argument) === "Symbol") throw new TypeError("Cannot convert a Symbol value to a string");
      return $String(argument);
    };
  }
});

// node_modules/core-js-pure/internals/validate-arguments-length.js
var require_validate_arguments_length = __commonJS({
  "node_modules/core-js-pure/internals/validate-arguments-length.js"(exports, module) {
    "use strict";
    var $TypeError = TypeError;
    module.exports = function(passed, required) {
      if (passed < required) throw new $TypeError("Not enough arguments");
      return passed;
    };
  }
});

// node_modules/core-js-pure/internals/base64-map.js
var require_base64_map = __commonJS({
  "node_modules/core-js-pure/internals/base64-map.js"(exports, module) {
    "use strict";
    var commonAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    var base64Alphabet = commonAlphabet + "+/";
    var base64UrlAlphabet = commonAlphabet + "-_";
    var inverse = function(characters) {
      var result = {};
      var index = 0;
      for (; index < 64; index++) result[characters.charAt(index)] = index;
      return result;
    };
    module.exports = {
      i2c: base64Alphabet,
      c2i: inverse(base64Alphabet),
      i2cUrl: base64UrlAlphabet,
      c2iUrl: inverse(base64UrlAlphabet)
    };
  }
});

// node_modules/core-js-pure/modules/web.atob.js
var require_web_atob = __commonJS({
  "node_modules/core-js-pure/modules/web.atob.js"() {
    "use strict";
    var $ = require_export();
    var globalThis2 = require_global_this();
    var getBuiltIn = require_get_built_in();
    var uncurryThis = require_function_uncurry_this();
    var call = require_function_call();
    var fails = require_fails();
    var toString = require_to_string();
    var validateArgumentsLength = require_validate_arguments_length();
    var c2i = require_base64_map().c2i;
    var disallowed = /[^\d+/a-z]/i;
    var whitespaces = /[\t\n\f\r ]+/g;
    var finalEq = /[=]{1,2}$/;
    var $atob = getBuiltIn("atob");
    var $Array = Array;
    var fromCharCode = String.fromCharCode;
    var charAt = uncurryThis("".charAt);
    var replace = uncurryThis("".replace);
    var join = uncurryThis([].join);
    var exec = uncurryThis(disallowed.exec);
    var BASIC = !!$atob && !fails(function() {
      return $atob("aGk=") !== "hi";
    });
    var NO_SPACES_IGNORE = BASIC && fails(function() {
      return $atob(" ") !== "";
    });
    var NO_ENCODING_CHECK = BASIC && !fails(function() {
      $atob("a");
    });
    var NO_ARG_RECEIVING_CHECK = BASIC && !fails(function() {
      $atob();
    });
    var WRONG_ARITY = BASIC && $atob.length !== 1;
    var FORCED = !BASIC || NO_SPACES_IGNORE || NO_ENCODING_CHECK || NO_ARG_RECEIVING_CHECK || WRONG_ARITY;
    $({ global: true, bind: true, enumerable: true, forced: FORCED }, {
      atob: function atob2(data) {
        validateArgumentsLength(arguments.length, 1);
        if (BASIC && !NO_SPACES_IGNORE && !NO_ENCODING_CHECK) return call($atob, globalThis2, data);
        var string = replace(toString(data), whitespaces, "");
        var position = 0;
        var bc = 0;
        var length, chr, bs;
        if (!(string.length & 3)) {
          string = replace(string, finalEq, "");
        }
        length = string.length;
        var lenmod = length & 3;
        if (lenmod === 1 || exec(disallowed, string)) {
          throw new (getBuiltIn("DOMException"))("The string is not correctly encoded", "InvalidCharacterError");
        }
        var output = new $Array((length >> 2) * 3 + (lenmod ? lenmod - 1 : 0));
        var outputIndex = 0;
        while (position < length) {
          chr = charAt(string, position++);
          bs = bc & 3 ? (bs << 6) + c2i[chr] : c2i[chr];
          if (bc++ & 3) output[outputIndex++] = fromCharCode(255 & bs >> (-2 * bc & 6));
        }
        return join(output, "");
      }
    });
  }
});

// node_modules/core-js-pure/internals/environment.js
var require_environment = __commonJS({
  "node_modules/core-js-pure/internals/environment.js"(exports, module) {
    "use strict";
    var globalThis2 = require_global_this();
    var userAgent = require_environment_user_agent();
    var classof = require_classof_raw();
    var userAgentStartsWith = function(string) {
      return userAgent.slice(0, string.length) === string;
    };
    module.exports = (function() {
      if (userAgentStartsWith("Bun/")) return "BUN";
      if (userAgentStartsWith("Cloudflare-Workers")) return "CLOUDFLARE";
      if (userAgentStartsWith("Deno/")) return "DENO";
      if (userAgentStartsWith("Node.js/")) return "NODE";
      if (globalThis2.Bun && typeof Bun.version == "string") return "BUN";
      if (globalThis2.Deno && typeof Deno.version == "object") return "DENO";
      if (classof(globalThis2.process) === "process") return "NODE";
      if (globalThis2.window && globalThis2.document) return "BROWSER";
      return "REST";
    })();
  }
});

// node_modules/core-js-pure/internals/environment-is-node.js
var require_environment_is_node = __commonJS({
  "node_modules/core-js-pure/internals/environment-is-node.js"(exports, module) {
    "use strict";
    var ENVIRONMENT = require_environment();
    module.exports = ENVIRONMENT === "NODE";
  }
});

// node_modules/core-js-pure/internals/get-built-in-node-module.js
var require_get_built_in_node_module = __commonJS({
  "node_modules/core-js-pure/internals/get-built-in-node-module.js"(exports, module) {
    "use strict";
    var globalThis2 = require_global_this();
    var IS_NODE = require_environment_is_node();
    module.exports = function(name) {
      if (IS_NODE) {
        try {
          return globalThis2.process.getBuiltinModule(name);
        } catch (error) {
        }
        try {
          return Function('return require("' + name + '")')();
        } catch (error) {
        }
      }
    };
  }
});

// node_modules/core-js-pure/internals/math-trunc.js
var require_math_trunc = __commonJS({
  "node_modules/core-js-pure/internals/math-trunc.js"(exports, module) {
    "use strict";
    var ceil = Math.ceil;
    var floor = Math.floor;
    module.exports = Math.trunc || function trunc(x) {
      var n = +x;
      return (n > 0 ? floor : ceil)(n);
    };
  }
});

// node_modules/core-js-pure/internals/to-integer-or-infinity.js
var require_to_integer_or_infinity = __commonJS({
  "node_modules/core-js-pure/internals/to-integer-or-infinity.js"(exports, module) {
    "use strict";
    var trunc = require_math_trunc();
    module.exports = function(argument) {
      var number = +argument;
      return number !== number || number === 0 ? 0 : trunc(number);
    };
  }
});

// node_modules/core-js-pure/internals/to-absolute-index.js
var require_to_absolute_index = __commonJS({
  "node_modules/core-js-pure/internals/to-absolute-index.js"(exports, module) {
    "use strict";
    var toIntegerOrInfinity = require_to_integer_or_infinity();
    var max = Math.max;
    var min = Math.min;
    module.exports = function(index, length) {
      var integer = toIntegerOrInfinity(index);
      return integer < 0 ? max(integer + length, 0) : min(integer, length);
    };
  }
});

// node_modules/core-js-pure/internals/to-length.js
var require_to_length = __commonJS({
  "node_modules/core-js-pure/internals/to-length.js"(exports, module) {
    "use strict";
    var toIntegerOrInfinity = require_to_integer_or_infinity();
    var min = Math.min;
    module.exports = function(argument) {
      var len = toIntegerOrInfinity(argument);
      return len > 0 ? min(len, 9007199254740991) : 0;
    };
  }
});

// node_modules/core-js-pure/internals/length-of-array-like.js
var require_length_of_array_like = __commonJS({
  "node_modules/core-js-pure/internals/length-of-array-like.js"(exports, module) {
    "use strict";
    var toLength = require_to_length();
    module.exports = function(obj) {
      return toLength(obj.length);
    };
  }
});

// node_modules/core-js-pure/internals/array-includes.js
var require_array_includes = __commonJS({
  "node_modules/core-js-pure/internals/array-includes.js"(exports, module) {
    "use strict";
    var toIndexedObject = require_to_indexed_object();
    var toAbsoluteIndex = require_to_absolute_index();
    var lengthOfArrayLike = require_length_of_array_like();
    var createMethod = function(IS_INCLUDES) {
      return function($this, el, fromIndex) {
        var O = toIndexedObject($this);
        var length = lengthOfArrayLike(O);
        if (length === 0) return !IS_INCLUDES && -1;
        var index = toAbsoluteIndex(fromIndex, length);
        var value;
        if (IS_INCLUDES && el !== el) while (length > index) {
          value = O[index++];
          if (value !== value) return true;
        }
        else for (; length > index; index++) {
          if ((IS_INCLUDES || index in O) && O[index] === el) return IS_INCLUDES || index || 0;
        }
        return !IS_INCLUDES && -1;
      };
    };
    module.exports = {
      // `Array.prototype.includes` method
      // https://tc39.es/ecma262/#sec-array.prototype.includes
      includes: createMethod(true),
      // `Array.prototype.indexOf` method
      // https://tc39.es/ecma262/#sec-array.prototype.indexof
      indexOf: createMethod(false)
    };
  }
});

// node_modules/core-js-pure/internals/hidden-keys.js
var require_hidden_keys = __commonJS({
  "node_modules/core-js-pure/internals/hidden-keys.js"(exports, module) {
    "use strict";
    module.exports = {};
  }
});

// node_modules/core-js-pure/internals/object-keys-internal.js
var require_object_keys_internal = __commonJS({
  "node_modules/core-js-pure/internals/object-keys-internal.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this();
    var hasOwn = require_has_own_property();
    var toIndexedObject = require_to_indexed_object();
    var indexOf = require_array_includes().indexOf;
    var hiddenKeys = require_hidden_keys();
    var push = uncurryThis([].push);
    module.exports = function(object4, names2) {
      var O = toIndexedObject(object4);
      var i = 0;
      var result = [];
      var key2;
      for (key2 in O) !hasOwn(hiddenKeys, key2) && hasOwn(O, key2) && push(result, key2);
      while (names2.length > i) if (hasOwn(O, key2 = names2[i++])) {
        ~indexOf(result, key2) || push(result, key2);
      }
      return result;
    };
  }
});

// node_modules/core-js-pure/internals/enum-bug-keys.js
var require_enum_bug_keys = __commonJS({
  "node_modules/core-js-pure/internals/enum-bug-keys.js"(exports, module) {
    "use strict";
    module.exports = [
      "constructor",
      "hasOwnProperty",
      "isPrototypeOf",
      "propertyIsEnumerable",
      "toLocaleString",
      "toString",
      "valueOf"
    ];
  }
});

// node_modules/core-js-pure/internals/object-keys.js
var require_object_keys = __commonJS({
  "node_modules/core-js-pure/internals/object-keys.js"(exports, module) {
    "use strict";
    var internalObjectKeys = require_object_keys_internal();
    var enumBugKeys = require_enum_bug_keys();
    module.exports = Object.keys || function keys2(O) {
      return internalObjectKeys(O, enumBugKeys);
    };
  }
});

// node_modules/core-js-pure/internals/object-define-properties.js
var require_object_define_properties = __commonJS({
  "node_modules/core-js-pure/internals/object-define-properties.js"(exports) {
    "use strict";
    var DESCRIPTORS = require_descriptors();
    var V8_PROTOTYPE_DEFINE_BUG = require_v8_prototype_define_bug();
    var definePropertyModule = require_object_define_property();
    var anObject = require_an_object();
    var toIndexedObject = require_to_indexed_object();
    var objectKeys = require_object_keys();
    exports.f = DESCRIPTORS && !V8_PROTOTYPE_DEFINE_BUG ? Object.defineProperties : function defineProperties(O, Properties) {
      anObject(O);
      var props = toIndexedObject(Properties);
      var keys2 = objectKeys(Properties);
      var length = keys2.length;
      var index = 0;
      var key2;
      while (length > index) definePropertyModule.f(O, key2 = keys2[index++], props[key2]);
      return O;
    };
  }
});

// node_modules/core-js-pure/internals/html.js
var require_html = __commonJS({
  "node_modules/core-js-pure/internals/html.js"(exports, module) {
    "use strict";
    var getBuiltIn = require_get_built_in();
    module.exports = getBuiltIn("document", "documentElement");
  }
});

// node_modules/core-js-pure/internals/shared-key.js
var require_shared_key = __commonJS({
  "node_modules/core-js-pure/internals/shared-key.js"(exports, module) {
    "use strict";
    var shared = require_shared();
    var uid = require_uid();
    var keys2 = shared("keys");
    module.exports = function(key2) {
      return keys2[key2] || (keys2[key2] = uid(key2));
    };
  }
});

// node_modules/core-js-pure/internals/object-create.js
var require_object_create = __commonJS({
  "node_modules/core-js-pure/internals/object-create.js"(exports, module) {
    "use strict";
    var anObject = require_an_object();
    var definePropertiesModule = require_object_define_properties();
    var enumBugKeys = require_enum_bug_keys();
    var hiddenKeys = require_hidden_keys();
    var html = require_html();
    var documentCreateElement = require_document_create_element();
    var sharedKey = require_shared_key();
    var GT = ">";
    var LT = "<";
    var PROTOTYPE = "prototype";
    var SCRIPT = "script";
    var IE_PROTO = sharedKey("IE_PROTO");
    var EmptyConstructor = function() {
    };
    var scriptTag = function(content2) {
      return LT + SCRIPT + GT + content2 + LT + "/" + SCRIPT + GT;
    };
    var NullProtoObjectViaActiveX = function(activeXDocument2) {
      activeXDocument2.write(scriptTag(""));
      activeXDocument2.close();
      var temp = activeXDocument2.parentWindow.Object;
      activeXDocument2 = null;
      return temp;
    };
    var NullProtoObjectViaIFrame = function() {
      var iframe = documentCreateElement("iframe");
      var JS = "java" + SCRIPT + ":";
      var iframeDocument;
      iframe.style.display = "none";
      html.appendChild(iframe);
      iframe.src = String(JS);
      iframeDocument = iframe.contentWindow.document;
      iframeDocument.open();
      iframeDocument.write(scriptTag("document.F=Object"));
      iframeDocument.close();
      return iframeDocument.F;
    };
    var activeXDocument;
    var NullProtoObject = function() {
      try {
        activeXDocument = new ActiveXObject("htmlfile");
      } catch (error) {
      }
      NullProtoObject = typeof document != "undefined" ? document.domain && activeXDocument ? NullProtoObjectViaActiveX(activeXDocument) : NullProtoObjectViaIFrame() : NullProtoObjectViaActiveX(activeXDocument);
      var length = enumBugKeys.length;
      while (length--) delete NullProtoObject[PROTOTYPE][enumBugKeys[length]];
      return NullProtoObject();
    };
    hiddenKeys[IE_PROTO] = true;
    module.exports = Object.create || function create(O, Properties) {
      var result;
      if (O !== null) {
        EmptyConstructor[PROTOTYPE] = anObject(O);
        result = new EmptyConstructor();
        EmptyConstructor[PROTOTYPE] = null;
        result[IE_PROTO] = O;
      } else result = NullProtoObject();
      return Properties === void 0 ? result : definePropertiesModule.f(result, Properties);
    };
  }
});

// node_modules/core-js-pure/internals/define-built-in.js
var require_define_built_in = __commonJS({
  "node_modules/core-js-pure/internals/define-built-in.js"(exports, module) {
    "use strict";
    var createNonEnumerableProperty = require_create_non_enumerable_property();
    module.exports = function(target, key2, value, options) {
      if (options && options.enumerable) target[key2] = value;
      else createNonEnumerableProperty(target, key2, value);
      return target;
    };
  }
});

// node_modules/core-js-pure/internals/define-built-in-accessor.js
var require_define_built_in_accessor = __commonJS({
  "node_modules/core-js-pure/internals/define-built-in-accessor.js"(exports, module) {
    "use strict";
    var defineProperty = require_object_define_property();
    module.exports = function(target, name, descriptor) {
      return defineProperty.f(target, name, descriptor);
    };
  }
});

// node_modules/core-js-pure/internals/an-instance.js
var require_an_instance = __commonJS({
  "node_modules/core-js-pure/internals/an-instance.js"(exports, module) {
    "use strict";
    var isPrototypeOf = require_object_is_prototype_of();
    var $TypeError = TypeError;
    module.exports = function(it, Prototype) {
      if (isPrototypeOf(Prototype, it)) return it;
      throw new $TypeError("Incorrect invocation");
    };
  }
});

// node_modules/core-js-pure/internals/normalize-string-argument.js
var require_normalize_string_argument = __commonJS({
  "node_modules/core-js-pure/internals/normalize-string-argument.js"(exports, module) {
    "use strict";
    var toString = require_to_string();
    module.exports = function(argument, $default) {
      return argument === void 0 ? arguments.length < 2 ? "" : $default : toString(argument);
    };
  }
});

// node_modules/core-js-pure/internals/error-to-string.js
var require_error_to_string = __commonJS({
  "node_modules/core-js-pure/internals/error-to-string.js"(exports, module) {
    "use strict";
    var DESCRIPTORS = require_descriptors();
    var fails = require_fails();
    var anObject = require_an_object();
    var normalizeStringArgument = require_normalize_string_argument();
    var nativeErrorToString = Error.prototype.toString;
    var INCORRECT_TO_STRING = fails(function() {
      if (DESCRIPTORS) {
        var object4 = Object.create(Object.defineProperty({}, "name", { get: function() {
          return this === object4;
        } }));
        if (nativeErrorToString.call(object4) !== "true") return true;
      }
      return nativeErrorToString.call({ message: 1, name: 2 }) !== "2: 1" || nativeErrorToString.call({}) !== "Error";
    });
    module.exports = INCORRECT_TO_STRING ? function toString() {
      var O = anObject(this);
      var name = normalizeStringArgument(O.name, "Error");
      var message = normalizeStringArgument(O.message);
      return !name ? message : !message ? name : name + ": " + message;
    } : nativeErrorToString;
  }
});

// node_modules/core-js-pure/internals/dom-exception-constants.js
var require_dom_exception_constants = __commonJS({
  "node_modules/core-js-pure/internals/dom-exception-constants.js"(exports, module) {
    "use strict";
    module.exports = {
      IndexSizeError: { s: "INDEX_SIZE_ERR", c: 1, m: 1 },
      DOMStringSizeError: { s: "DOMSTRING_SIZE_ERR", c: 2, m: 0 },
      HierarchyRequestError: { s: "HIERARCHY_REQUEST_ERR", c: 3, m: 1 },
      WrongDocumentError: { s: "WRONG_DOCUMENT_ERR", c: 4, m: 1 },
      InvalidCharacterError: { s: "INVALID_CHARACTER_ERR", c: 5, m: 1 },
      NoDataAllowedError: { s: "NO_DATA_ALLOWED_ERR", c: 6, m: 0 },
      NoModificationAllowedError: { s: "NO_MODIFICATION_ALLOWED_ERR", c: 7, m: 1 },
      NotFoundError: { s: "NOT_FOUND_ERR", c: 8, m: 1 },
      NotSupportedError: { s: "NOT_SUPPORTED_ERR", c: 9, m: 1 },
      InUseAttributeError: { s: "INUSE_ATTRIBUTE_ERR", c: 10, m: 1 },
      InvalidStateError: { s: "INVALID_STATE_ERR", c: 11, m: 1 },
      SyntaxError: { s: "SYNTAX_ERR", c: 12, m: 1 },
      InvalidModificationError: { s: "INVALID_MODIFICATION_ERR", c: 13, m: 1 },
      NamespaceError: { s: "NAMESPACE_ERR", c: 14, m: 1 },
      InvalidAccessError: { s: "INVALID_ACCESS_ERR", c: 15, m: 1 },
      ValidationError: { s: "VALIDATION_ERR", c: 16, m: 0 },
      TypeMismatchError: { s: "TYPE_MISMATCH_ERR", c: 17, m: 1 },
      SecurityError: { s: "SECURITY_ERR", c: 18, m: 1 },
      NetworkError: { s: "NETWORK_ERR", c: 19, m: 1 },
      AbortError: { s: "ABORT_ERR", c: 20, m: 1 },
      URLMismatchError: { s: "URL_MISMATCH_ERR", c: 21, m: 1 },
      QuotaExceededError: { s: "QUOTA_EXCEEDED_ERR", c: 22, m: 1 },
      TimeoutError: { s: "TIMEOUT_ERR", c: 23, m: 1 },
      InvalidNodeTypeError: { s: "INVALID_NODE_TYPE_ERR", c: 24, m: 1 },
      DataCloneError: { s: "DATA_CLONE_ERR", c: 25, m: 1 }
    };
  }
});

// node_modules/core-js-pure/internals/error-stack-clear.js
var require_error_stack_clear = __commonJS({
  "node_modules/core-js-pure/internals/error-stack-clear.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this();
    var $Error = Error;
    var replace = uncurryThis("".replace);
    var TEST = (function(arg) {
      return String(new $Error(arg).stack);
    })("zxcasd");
    var V8_OR_CHAKRA_STACK_ENTRY = /\n\s*at [^:]*:[^\n]*/;
    var IS_V8_OR_CHAKRA_STACK = V8_OR_CHAKRA_STACK_ENTRY.test(TEST);
    module.exports = function(stack, dropEntries) {
      if (IS_V8_OR_CHAKRA_STACK && typeof stack == "string" && !$Error.prepareStackTrace) {
        while (dropEntries--) stack = replace(stack, V8_OR_CHAKRA_STACK_ENTRY, "");
      }
      return stack;
    };
  }
});

// node_modules/core-js-pure/internals/weak-map-basic-detection.js
var require_weak_map_basic_detection = __commonJS({
  "node_modules/core-js-pure/internals/weak-map-basic-detection.js"(exports, module) {
    "use strict";
    var globalThis2 = require_global_this();
    var isCallable = require_is_callable();
    var WeakMap2 = globalThis2.WeakMap;
    module.exports = isCallable(WeakMap2) && /native code/.test(String(WeakMap2));
  }
});

// node_modules/core-js-pure/internals/internal-state.js
var require_internal_state = __commonJS({
  "node_modules/core-js-pure/internals/internal-state.js"(exports, module) {
    "use strict";
    var NATIVE_WEAK_MAP = require_weak_map_basic_detection();
    var globalThis2 = require_global_this();
    var isObject = require_is_object();
    var createNonEnumerableProperty = require_create_non_enumerable_property();
    var hasOwn = require_has_own_property();
    var shared = require_shared_store();
    var sharedKey = require_shared_key();
    var hiddenKeys = require_hidden_keys();
    var OBJECT_ALREADY_INITIALIZED = "Object already initialized";
    var TypeError2 = globalThis2.TypeError;
    var WeakMap2 = globalThis2.WeakMap;
    var set;
    var get;
    var has;
    var enforce = function(it) {
      return has(it) ? get(it) : set(it, {});
    };
    var getterFor = function(TYPE) {
      return function(it) {
        var state;
        if (!isObject(it) || (state = get(it)).type !== TYPE) {
          throw new TypeError2("Incompatible receiver, " + TYPE + " required");
        }
        return state;
      };
    };
    if (NATIVE_WEAK_MAP || shared.state) {
      store = shared.state || (shared.state = new WeakMap2());
      store.get = store.get;
      store.has = store.has;
      store.set = store.set;
      set = function(it, metadata) {
        if (store.has(it)) throw new TypeError2(OBJECT_ALREADY_INITIALIZED);
        metadata.facade = it;
        store.set(it, metadata);
        return metadata;
      };
      get = function(it) {
        return store.get(it) || {};
      };
      has = function(it) {
        return store.has(it);
      };
    } else {
      STATE = sharedKey("state");
      hiddenKeys[STATE] = true;
      set = function(it, metadata) {
        if (hasOwn(it, STATE)) throw new TypeError2(OBJECT_ALREADY_INITIALIZED);
        metadata.facade = it;
        createNonEnumerableProperty(it, STATE, metadata);
        return metadata;
      };
      get = function(it) {
        return hasOwn(it, STATE) ? it[STATE] : {};
      };
      has = function(it) {
        return hasOwn(it, STATE);
      };
    }
    var store;
    var STATE;
    module.exports = {
      set,
      get,
      has,
      enforce,
      getterFor
    };
  }
});

// node_modules/core-js-pure/modules/web.dom-exception.constructor.js
var require_web_dom_exception_constructor = __commonJS({
  "node_modules/core-js-pure/modules/web.dom-exception.constructor.js"() {
    "use strict";
    var $ = require_export();
    var getBuiltIn = require_get_built_in();
    var getBuiltInNodeModule = require_get_built_in_node_module();
    var fails = require_fails();
    var create = require_object_create();
    var createPropertyDescriptor = require_create_property_descriptor();
    var defineProperty = require_object_define_property().f;
    var defineBuiltIn = require_define_built_in();
    var defineBuiltInAccessor = require_define_built_in_accessor();
    var hasOwn = require_has_own_property();
    var anInstance = require_an_instance();
    var anObject = require_an_object();
    var errorToString = require_error_to_string();
    var normalizeStringArgument = require_normalize_string_argument();
    var DOMExceptionConstants = require_dom_exception_constants();
    var clearErrorStack = require_error_stack_clear();
    var InternalStateModule = require_internal_state();
    var DESCRIPTORS = require_descriptors();
    var IS_PURE = require_is_pure();
    var DOM_EXCEPTION = "DOMException";
    var DATA_CLONE_ERR = "DATA_CLONE_ERR";
    var Error2 = getBuiltIn("Error");
    var NativeDOMException = getBuiltIn(DOM_EXCEPTION) || (function() {
      try {
        var MessageChannel = getBuiltIn("MessageChannel") || getBuiltInNodeModule("worker_threads").MessageChannel;
        new MessageChannel().port1.postMessage(/* @__PURE__ */ new WeakMap());
      } catch (error) {
        if (error.name === DATA_CLONE_ERR && error.code === 25) return error.constructor;
      }
    })();
    var NativeDOMExceptionPrototype = NativeDOMException && NativeDOMException.prototype;
    var ErrorPrototype = Error2.prototype;
    var setInternalState = InternalStateModule.set;
    var getInternalState = InternalStateModule.getterFor(DOM_EXCEPTION);
    var HAS_STACK = "stack" in new Error2(DOM_EXCEPTION);
    var codeFor = function(name) {
      return hasOwn(DOMExceptionConstants, name) && DOMExceptionConstants[name].m ? DOMExceptionConstants[name].c : 0;
    };
    var $DOMException = function DOMException() {
      anInstance(this, DOMExceptionPrototype);
      var argumentsLength = arguments.length;
      var message = normalizeStringArgument(argumentsLength < 1 ? void 0 : arguments[0]);
      var name = normalizeStringArgument(argumentsLength < 2 ? void 0 : arguments[1], "Error");
      var code = codeFor(name);
      setInternalState(this, {
        type: DOM_EXCEPTION,
        name,
        message,
        code
      });
      if (!DESCRIPTORS) {
        this.name = name;
        this.message = message;
        this.code = code;
      }
      if (HAS_STACK) {
        var error = new Error2(message);
        error.name = DOM_EXCEPTION;
        defineProperty(this, "stack", createPropertyDescriptor(1, clearErrorStack(error.stack, 1)));
      }
    };
    var DOMExceptionPrototype = $DOMException.prototype = create(ErrorPrototype);
    var createGetterDescriptor = function(get) {
      return { enumerable: true, configurable: true, get };
    };
    var getterFor = function(key3) {
      return createGetterDescriptor(function() {
        return getInternalState(this)[key3];
      });
    };
    if (DESCRIPTORS) {
      defineBuiltInAccessor(DOMExceptionPrototype, "code", getterFor("code"));
      defineBuiltInAccessor(DOMExceptionPrototype, "message", getterFor("message"));
      defineBuiltInAccessor(DOMExceptionPrototype, "name", getterFor("name"));
    }
    defineProperty(DOMExceptionPrototype, "constructor", createPropertyDescriptor(1, $DOMException));
    var INCORRECT_CONSTRUCTOR = fails(function() {
      return !(new NativeDOMException() instanceof Error2);
    });
    var INCORRECT_TO_STRING = INCORRECT_CONSTRUCTOR || fails(function() {
      return ErrorPrototype.toString !== errorToString || String(new NativeDOMException(1, 2)) !== "2: 1";
    });
    var INCORRECT_CODE = INCORRECT_CONSTRUCTOR || fails(function() {
      return new NativeDOMException(1, "DataCloneError").code !== 25;
    });
    var MISSED_CONSTANTS = INCORRECT_CONSTRUCTOR || NativeDOMException[DATA_CLONE_ERR] !== 25 || NativeDOMExceptionPrototype[DATA_CLONE_ERR] !== 25;
    var FORCED_CONSTRUCTOR = IS_PURE ? INCORRECT_TO_STRING || INCORRECT_CODE || MISSED_CONSTANTS : INCORRECT_CONSTRUCTOR;
    $({ global: true, constructor: true, forced: FORCED_CONSTRUCTOR }, {
      DOMException: FORCED_CONSTRUCTOR ? $DOMException : NativeDOMException
    });
    var PolyfilledDOMException = getBuiltIn(DOM_EXCEPTION);
    var PolyfilledDOMExceptionPrototype = PolyfilledDOMException.prototype;
    if (INCORRECT_TO_STRING && (IS_PURE || NativeDOMException === PolyfilledDOMException)) {
      defineBuiltIn(PolyfilledDOMExceptionPrototype, "toString", errorToString);
    }
    if (INCORRECT_CODE && DESCRIPTORS && NativeDOMException === PolyfilledDOMException) {
      defineBuiltInAccessor(PolyfilledDOMExceptionPrototype, "code", createGetterDescriptor(function() {
        return codeFor(anObject(this).name);
      }));
    }
    for (key2 in DOMExceptionConstants) if (hasOwn(DOMExceptionConstants, key2)) {
      constant = DOMExceptionConstants[key2];
      constantName = constant.s;
      descriptor = createPropertyDescriptor(6, constant.c);
      if (!hasOwn(PolyfilledDOMException, constantName)) {
        defineProperty(PolyfilledDOMException, constantName, descriptor);
      }
      if (!hasOwn(PolyfilledDOMExceptionPrototype, constantName)) {
        defineProperty(PolyfilledDOMExceptionPrototype, constantName, descriptor);
      }
    }
    var constant;
    var constantName;
    var descriptor;
    var key2;
  }
});

// node_modules/core-js-pure/internals/function-uncurry-this-accessor.js
var require_function_uncurry_this_accessor = __commonJS({
  "node_modules/core-js-pure/internals/function-uncurry-this-accessor.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this();
    var aCallable = require_a_callable();
    module.exports = function(object4, key2, method) {
      try {
        return uncurryThis(aCallable(Object.getOwnPropertyDescriptor(object4, key2)[method]));
      } catch (error) {
      }
    };
  }
});

// node_modules/core-js-pure/internals/is-possible-prototype.js
var require_is_possible_prototype = __commonJS({
  "node_modules/core-js-pure/internals/is-possible-prototype.js"(exports, module) {
    "use strict";
    var isObject = require_is_object();
    module.exports = function(argument) {
      return isObject(argument) || argument === null;
    };
  }
});

// node_modules/core-js-pure/internals/a-possible-prototype.js
var require_a_possible_prototype = __commonJS({
  "node_modules/core-js-pure/internals/a-possible-prototype.js"(exports, module) {
    "use strict";
    var isPossiblePrototype = require_is_possible_prototype();
    var $String = String;
    var $TypeError = TypeError;
    module.exports = function(argument) {
      if (isPossiblePrototype(argument)) return argument;
      throw new $TypeError("Can't set " + $String(argument) + " as a prototype");
    };
  }
});

// node_modules/core-js-pure/internals/object-set-prototype-of.js
var require_object_set_prototype_of = __commonJS({
  "node_modules/core-js-pure/internals/object-set-prototype-of.js"(exports, module) {
    "use strict";
    var uncurryThisAccessor = require_function_uncurry_this_accessor();
    var isObject = require_is_object();
    var requireObjectCoercible = require_require_object_coercible();
    var aPossiblePrototype = require_a_possible_prototype();
    module.exports = Object.setPrototypeOf || ("__proto__" in {} ? (function() {
      var CORRECT_SETTER = false;
      var test = {};
      var setter;
      try {
        setter = uncurryThisAccessor(Object.prototype, "__proto__", "set");
        setter(test, []);
        CORRECT_SETTER = test instanceof Array;
      } catch (error) {
      }
      return function setPrototypeOf(O, proto) {
        requireObjectCoercible(O);
        aPossiblePrototype(proto);
        if (!isObject(O)) return O;
        if (CORRECT_SETTER) setter(O, proto);
        else O.__proto__ = proto;
        return O;
      };
    })() : void 0);
  }
});

// node_modules/core-js-pure/internals/inherit-if-required.js
var require_inherit_if_required = __commonJS({
  "node_modules/core-js-pure/internals/inherit-if-required.js"(exports, module) {
    "use strict";
    var isCallable = require_is_callable();
    var isObject = require_is_object();
    var setPrototypeOf = require_object_set_prototype_of();
    module.exports = function($this, dummy, Wrapper) {
      var NewTarget, NewTargetPrototype;
      if (
        // it can work only with native `setPrototypeOf`
        setPrototypeOf && // we haven't completely correct pre-ES6 way for getting `new.target`, so use this
        isCallable(NewTarget = dummy.constructor) && NewTarget !== Wrapper && isObject(NewTargetPrototype = NewTarget.prototype) && NewTargetPrototype !== Wrapper.prototype
      ) setPrototypeOf($this, NewTargetPrototype);
      return $this;
    };
  }
});

// node_modules/core-js-pure/modules/web.dom-exception.stack.js
var require_web_dom_exception_stack = __commonJS({
  "node_modules/core-js-pure/modules/web.dom-exception.stack.js"() {
    "use strict";
    var $ = require_export();
    var globalThis2 = require_global_this();
    var getBuiltIn = require_get_built_in();
    var createPropertyDescriptor = require_create_property_descriptor();
    var defineProperty = require_object_define_property().f;
    var hasOwn = require_has_own_property();
    var anInstance = require_an_instance();
    var inheritIfRequired = require_inherit_if_required();
    var normalizeStringArgument = require_normalize_string_argument();
    var DOMExceptionConstants = require_dom_exception_constants();
    var clearErrorStack = require_error_stack_clear();
    var DESCRIPTORS = require_descriptors();
    var IS_PURE = require_is_pure();
    var DOM_EXCEPTION = "DOMException";
    var Error2 = getBuiltIn("Error");
    var NativeDOMException = getBuiltIn(DOM_EXCEPTION);
    var $DOMException = function DOMException() {
      anInstance(this, DOMExceptionPrototype);
      var argumentsLength = arguments.length;
      var message = normalizeStringArgument(argumentsLength < 1 ? void 0 : arguments[0]);
      var name = normalizeStringArgument(argumentsLength < 2 ? void 0 : arguments[1], "Error");
      var that = new NativeDOMException(message, name);
      var error = new Error2(message);
      error.name = DOM_EXCEPTION;
      defineProperty(that, "stack", createPropertyDescriptor(1, clearErrorStack(error.stack, 1)));
      inheritIfRequired(that, this, $DOMException);
      return that;
    };
    var DOMExceptionPrototype = $DOMException.prototype = NativeDOMException.prototype;
    var ERROR_HAS_STACK = "stack" in new Error2(DOM_EXCEPTION);
    var DOM_EXCEPTION_HAS_STACK = "stack" in new NativeDOMException(1, 2);
    var descriptor = NativeDOMException && DESCRIPTORS && Object.getOwnPropertyDescriptor(globalThis2, DOM_EXCEPTION);
    var BUGGY_DESCRIPTOR = !!descriptor && !(descriptor.writable && descriptor.configurable);
    var FORCED_CONSTRUCTOR = ERROR_HAS_STACK && !BUGGY_DESCRIPTOR && !DOM_EXCEPTION_HAS_STACK;
    $({ global: true, constructor: true, forced: IS_PURE || FORCED_CONSTRUCTOR }, {
      // TODO: fix export logic
      DOMException: FORCED_CONSTRUCTOR ? $DOMException : NativeDOMException
    });
    var PolyfilledDOMException = getBuiltIn(DOM_EXCEPTION);
    var PolyfilledDOMExceptionPrototype = PolyfilledDOMException.prototype;
    if (PolyfilledDOMExceptionPrototype.constructor !== PolyfilledDOMException) {
      if (!IS_PURE) {
        defineProperty(PolyfilledDOMExceptionPrototype, "constructor", createPropertyDescriptor(1, PolyfilledDOMException));
      }
      for (key2 in DOMExceptionConstants) if (hasOwn(DOMExceptionConstants, key2)) {
        constant = DOMExceptionConstants[key2];
        constantName = constant.s;
        if (!hasOwn(PolyfilledDOMException, constantName)) {
          defineProperty(PolyfilledDOMException, constantName, createPropertyDescriptor(6, constant.c));
        }
      }
    }
    var constant;
    var constantName;
    var key2;
  }
});

// node_modules/core-js-pure/internals/object-to-string.js
var require_object_to_string = __commonJS({
  "node_modules/core-js-pure/internals/object-to-string.js"(exports, module) {
    "use strict";
    var TO_STRING_TAG_SUPPORT = require_to_string_tag_support();
    var classof = require_classof();
    module.exports = TO_STRING_TAG_SUPPORT ? {}.toString : function toString() {
      return "[object " + classof(this) + "]";
    };
  }
});

// node_modules/core-js-pure/internals/set-to-string-tag.js
var require_set_to_string_tag = __commonJS({
  "node_modules/core-js-pure/internals/set-to-string-tag.js"(exports, module) {
    "use strict";
    var TO_STRING_TAG_SUPPORT = require_to_string_tag_support();
    var defineProperty = require_object_define_property().f;
    var createNonEnumerableProperty = require_create_non_enumerable_property();
    var hasOwn = require_has_own_property();
    var toString = require_object_to_string();
    var wellKnownSymbol = require_well_known_symbol();
    var TO_STRING_TAG = wellKnownSymbol("toStringTag");
    module.exports = function(it, TAG, STATIC, SET_METHOD) {
      var target = STATIC ? it : it && it.prototype;
      if (target) {
        if (!hasOwn(target, TO_STRING_TAG)) {
          defineProperty(target, TO_STRING_TAG, { configurable: true, value: TAG });
        }
        if (SET_METHOD && !TO_STRING_TAG_SUPPORT) {
          createNonEnumerableProperty(target, "toString", toString);
        }
      }
    };
  }
});

// node_modules/core-js-pure/modules/web.dom-exception.to-string-tag.js
var require_web_dom_exception_to_string_tag = __commonJS({
  "node_modules/core-js-pure/modules/web.dom-exception.to-string-tag.js"() {
    "use strict";
    var getBuiltIn = require_get_built_in();
    var setToStringTag = require_set_to_string_tag();
    var DOM_EXCEPTION = "DOMException";
    setToStringTag(getBuiltIn(DOM_EXCEPTION), DOM_EXCEPTION);
  }
});

// node_modules/core-js-pure/stable/atob.js
var require_atob = __commonJS({
  "node_modules/core-js-pure/stable/atob.js"(exports, module) {
    "use strict";
    require_es_error_to_string();
    require_es_object_to_string();
    require_web_atob();
    require_web_dom_exception_constructor();
    require_web_dom_exception_stack();
    require_web_dom_exception_to_string_tag();
    var path = require_path();
    module.exports = path.atob;
  }
});

// node_modules/core-js-pure/actual/atob.js
var require_atob2 = __commonJS({
  "node_modules/core-js-pure/actual/atob.js"(exports, module) {
    "use strict";
    var parent2 = require_atob();
    module.exports = parent2;
  }
});

// node_modules/core-js-pure/modules/web.btoa.js
var require_web_btoa = __commonJS({
  "node_modules/core-js-pure/modules/web.btoa.js"() {
    "use strict";
    var $ = require_export();
    var globalThis2 = require_global_this();
    var getBuiltIn = require_get_built_in();
    var uncurryThis = require_function_uncurry_this();
    var call = require_function_call();
    var fails = require_fails();
    var toString = require_to_string();
    var validateArgumentsLength = require_validate_arguments_length();
    var i2c = require_base64_map().i2c;
    var $btoa = getBuiltIn("btoa");
    var $Array = Array;
    var join = uncurryThis([].join);
    var charAt = uncurryThis("".charAt);
    var charCodeAt = uncurryThis("".charCodeAt);
    var BASIC = !!$btoa && !fails(function() {
      return $btoa("hi") !== "aGk=";
    });
    var NO_ARG_RECEIVING_CHECK = BASIC && !fails(function() {
      $btoa();
    });
    var WRONG_ARG_CONVERSION = BASIC && fails(function() {
      return $btoa(null) !== "bnVsbA==";
    });
    var WRONG_ARITY = BASIC && $btoa.length !== 1;
    $({ global: true, bind: true, enumerable: true, forced: !BASIC || NO_ARG_RECEIVING_CHECK || WRONG_ARG_CONVERSION || WRONG_ARITY }, {
      btoa: function btoa2(data) {
        validateArgumentsLength(arguments.length, 1);
        if (BASIC) return call($btoa, globalThis2, toString(data));
        var string = toString(data);
        var output = new $Array((string.length + 2) / 3 << 2);
        var outputIndex = 0;
        var position = 0;
        var map = i2c;
        var block, charCode;
        while (charAt(string, position) || (map = "=", position % 1)) {
          charCode = charCodeAt(string, position += 3 / 4);
          if (charCode > 255) {
            throw new (getBuiltIn("DOMException"))("The string contains characters outside of the Latin1 range", "InvalidCharacterError");
          }
          block = block << 8 | charCode;
          output[outputIndex++] = charAt(map, 63 & block >> 8 - position % 1 * 8);
        }
        return join(output, "");
      }
    });
  }
});

// node_modules/core-js-pure/stable/btoa.js
var require_btoa = __commonJS({
  "node_modules/core-js-pure/stable/btoa.js"(exports, module) {
    "use strict";
    require_es_error_to_string();
    require_es_object_to_string();
    require_web_btoa();
    require_web_dom_exception_constructor();
    require_web_dom_exception_stack();
    require_web_dom_exception_to_string_tag();
    var path = require_path();
    module.exports = path.btoa;
  }
});

// node_modules/core-js-pure/actual/btoa.js
var require_btoa2 = __commonJS({
  "node_modules/core-js-pure/actual/btoa.js"(exports, module) {
    "use strict";
    var parent2 = require_btoa();
    module.exports = parent2;
  }
});

// node_modules/core-js-pure/internals/add-to-unscopables.js
var require_add_to_unscopables = __commonJS({
  "node_modules/core-js-pure/internals/add-to-unscopables.js"(exports, module) {
    "use strict";
    module.exports = function() {
    };
  }
});

// node_modules/core-js-pure/internals/iterators.js
var require_iterators = __commonJS({
  "node_modules/core-js-pure/internals/iterators.js"(exports, module) {
    "use strict";
    module.exports = Object.create ? /* @__PURE__ */ Object.create(null) : {};
  }
});

// node_modules/core-js-pure/internals/function-name.js
var require_function_name = __commonJS({
  "node_modules/core-js-pure/internals/function-name.js"(exports, module) {
    "use strict";
    var DESCRIPTORS = require_descriptors();
    var hasOwn = require_has_own_property();
    var FunctionPrototype = Function.prototype;
    var getDescriptor = DESCRIPTORS && Object.getOwnPropertyDescriptor;
    var EXISTS = hasOwn(FunctionPrototype, "name");
    var PROPER = EXISTS && function something() {
    }.name === "something";
    var CONFIGURABLE = EXISTS && (!DESCRIPTORS || DESCRIPTORS && getDescriptor(FunctionPrototype, "name").configurable);
    module.exports = {
      EXISTS,
      PROPER,
      CONFIGURABLE
    };
  }
});

// node_modules/core-js-pure/internals/correct-prototype-getter.js
var require_correct_prototype_getter = __commonJS({
  "node_modules/core-js-pure/internals/correct-prototype-getter.js"(exports, module) {
    "use strict";
    var fails = require_fails();
    module.exports = !fails(function() {
      function F() {
      }
      F.prototype.constructor = null;
      return Object.getPrototypeOf(new F()) !== F.prototype;
    });
  }
});

// node_modules/core-js-pure/internals/object-get-prototype-of.js
var require_object_get_prototype_of = __commonJS({
  "node_modules/core-js-pure/internals/object-get-prototype-of.js"(exports, module) {
    "use strict";
    var hasOwn = require_has_own_property();
    var isCallable = require_is_callable();
    var toObject = require_to_object();
    var sharedKey = require_shared_key();
    var CORRECT_PROTOTYPE_GETTER = require_correct_prototype_getter();
    var IE_PROTO = sharedKey("IE_PROTO");
    var $Object = Object;
    var ObjectPrototype = $Object.prototype;
    module.exports = CORRECT_PROTOTYPE_GETTER ? $Object.getPrototypeOf : function(O) {
      var object4 = toObject(O);
      if (hasOwn(object4, IE_PROTO)) return object4[IE_PROTO];
      var constructor = object4.constructor;
      if (isCallable(constructor) && object4 instanceof constructor) {
        return constructor.prototype;
      }
      return object4 instanceof $Object ? ObjectPrototype : null;
    };
  }
});

// node_modules/core-js-pure/internals/iterators-core.js
var require_iterators_core = __commonJS({
  "node_modules/core-js-pure/internals/iterators-core.js"(exports, module) {
    "use strict";
    var fails = require_fails();
    var isCallable = require_is_callable();
    var isObject = require_is_object();
    var create = require_object_create();
    var getPrototypeOf = require_object_get_prototype_of();
    var defineBuiltIn = require_define_built_in();
    var wellKnownSymbol = require_well_known_symbol();
    var IS_PURE = require_is_pure();
    var ITERATOR = wellKnownSymbol("iterator");
    var BUGGY_SAFARI_ITERATORS = false;
    var IteratorPrototype;
    var PrototypeOfArrayIteratorPrototype;
    var arrayIterator;
    if ([].keys) {
      arrayIterator = [].keys();
      if (!("next" in arrayIterator)) BUGGY_SAFARI_ITERATORS = true;
      else {
        PrototypeOfArrayIteratorPrototype = getPrototypeOf(getPrototypeOf(arrayIterator));
        if (PrototypeOfArrayIteratorPrototype !== Object.prototype) IteratorPrototype = PrototypeOfArrayIteratorPrototype;
      }
    }
    var NEW_ITERATOR_PROTOTYPE = !isObject(IteratorPrototype) || fails(function() {
      var test = {};
      return IteratorPrototype[ITERATOR].call(test) !== test;
    });
    if (NEW_ITERATOR_PROTOTYPE) IteratorPrototype = {};
    else if (IS_PURE) IteratorPrototype = create(IteratorPrototype);
    if (!isCallable(IteratorPrototype[ITERATOR])) {
      defineBuiltIn(IteratorPrototype, ITERATOR, function() {
        return this;
      });
    }
    module.exports = {
      IteratorPrototype,
      BUGGY_SAFARI_ITERATORS
    };
  }
});

// node_modules/core-js-pure/internals/iterator-create-constructor.js
var require_iterator_create_constructor = __commonJS({
  "node_modules/core-js-pure/internals/iterator-create-constructor.js"(exports, module) {
    "use strict";
    var IteratorPrototype = require_iterators_core().IteratorPrototype;
    var create = require_object_create();
    var createPropertyDescriptor = require_create_property_descriptor();
    var setToStringTag = require_set_to_string_tag();
    var Iterators = require_iterators();
    var returnThis = function() {
      return this;
    };
    module.exports = function(IteratorConstructor, NAME, next, ENUMERABLE_NEXT) {
      var TO_STRING_TAG = NAME + " Iterator";
      IteratorConstructor.prototype = create(IteratorPrototype, { next: createPropertyDescriptor(+!ENUMERABLE_NEXT, next) });
      setToStringTag(IteratorConstructor, TO_STRING_TAG, false, true);
      Iterators[TO_STRING_TAG] = returnThis;
      return IteratorConstructor;
    };
  }
});

// node_modules/core-js-pure/internals/iterator-define.js
var require_iterator_define = __commonJS({
  "node_modules/core-js-pure/internals/iterator-define.js"(exports, module) {
    "use strict";
    var $ = require_export();
    var call = require_function_call();
    var IS_PURE = require_is_pure();
    var FunctionName = require_function_name();
    var isCallable = require_is_callable();
    var createIteratorConstructor = require_iterator_create_constructor();
    var getPrototypeOf = require_object_get_prototype_of();
    var setPrototypeOf = require_object_set_prototype_of();
    var setToStringTag = require_set_to_string_tag();
    var createNonEnumerableProperty = require_create_non_enumerable_property();
    var defineBuiltIn = require_define_built_in();
    var wellKnownSymbol = require_well_known_symbol();
    var Iterators = require_iterators();
    var IteratorsCore = require_iterators_core();
    var PROPER_FUNCTION_NAME = FunctionName.PROPER;
    var CONFIGURABLE_FUNCTION_NAME = FunctionName.CONFIGURABLE;
    var IteratorPrototype = IteratorsCore.IteratorPrototype;
    var BUGGY_SAFARI_ITERATORS = IteratorsCore.BUGGY_SAFARI_ITERATORS;
    var ITERATOR = wellKnownSymbol("iterator");
    var KEYS = "keys";
    var VALUES = "values";
    var ENTRIES = "entries";
    var returnThis = function() {
      return this;
    };
    module.exports = function(Iterable, NAME, IteratorConstructor, next, DEFAULT, IS_SET, FORCED) {
      createIteratorConstructor(IteratorConstructor, NAME, next);
      var getIterationMethod = function(KIND) {
        if (KIND === DEFAULT && defaultIterator) return defaultIterator;
        if (!BUGGY_SAFARI_ITERATORS && KIND && KIND in IterablePrototype) return IterablePrototype[KIND];
        switch (KIND) {
          case KEYS:
            return function keys2() {
              return new IteratorConstructor(this, KIND);
            };
          case VALUES:
            return function values() {
              return new IteratorConstructor(this, KIND);
            };
          case ENTRIES:
            return function entries() {
              return new IteratorConstructor(this, KIND);
            };
        }
        return function() {
          return new IteratorConstructor(this);
        };
      };
      var TO_STRING_TAG = NAME + " Iterator";
      var INCORRECT_VALUES_NAME = false;
      var IterablePrototype = Iterable.prototype;
      var nativeIterator = IterablePrototype[ITERATOR] || IterablePrototype["@@iterator"] || DEFAULT && IterablePrototype[DEFAULT];
      var defaultIterator = !BUGGY_SAFARI_ITERATORS && nativeIterator || getIterationMethod(DEFAULT);
      var anyNativeIterator = NAME === "Array" ? IterablePrototype.entries || nativeIterator : nativeIterator;
      var CurrentIteratorPrototype, methods, KEY;
      if (anyNativeIterator) {
        CurrentIteratorPrototype = getPrototypeOf(anyNativeIterator.call(new Iterable()));
        if (CurrentIteratorPrototype !== Object.prototype && CurrentIteratorPrototype.next) {
          if (!IS_PURE && getPrototypeOf(CurrentIteratorPrototype) !== IteratorPrototype) {
            if (setPrototypeOf) {
              setPrototypeOf(CurrentIteratorPrototype, IteratorPrototype);
            } else if (!isCallable(CurrentIteratorPrototype[ITERATOR])) {
              defineBuiltIn(CurrentIteratorPrototype, ITERATOR, returnThis);
            }
          }
          setToStringTag(CurrentIteratorPrototype, TO_STRING_TAG, true, true);
          if (IS_PURE) Iterators[TO_STRING_TAG] = returnThis;
        }
      }
      if (PROPER_FUNCTION_NAME && DEFAULT === VALUES && nativeIterator && nativeIterator.name !== VALUES) {
        if (!IS_PURE && CONFIGURABLE_FUNCTION_NAME) {
          createNonEnumerableProperty(IterablePrototype, "name", VALUES);
        } else {
          INCORRECT_VALUES_NAME = true;
          defaultIterator = function values() {
            return call(nativeIterator, this);
          };
        }
      }
      if (DEFAULT) {
        methods = {
          values: getIterationMethod(VALUES),
          keys: IS_SET ? defaultIterator : getIterationMethod(KEYS),
          entries: getIterationMethod(ENTRIES)
        };
        if (FORCED) for (KEY in methods) {
          if (BUGGY_SAFARI_ITERATORS || INCORRECT_VALUES_NAME || !(KEY in IterablePrototype)) {
            defineBuiltIn(IterablePrototype, KEY, methods[KEY]);
          }
        }
        else $({ target: NAME, proto: true, forced: BUGGY_SAFARI_ITERATORS || INCORRECT_VALUES_NAME }, methods);
      }
      if ((!IS_PURE || FORCED) && IterablePrototype[ITERATOR] !== defaultIterator) {
        defineBuiltIn(IterablePrototype, ITERATOR, defaultIterator, { name: DEFAULT });
      }
      Iterators[NAME] = defaultIterator;
      return methods;
    };
  }
});

// node_modules/core-js-pure/internals/create-iter-result-object.js
var require_create_iter_result_object = __commonJS({
  "node_modules/core-js-pure/internals/create-iter-result-object.js"(exports, module) {
    "use strict";
    module.exports = function(value, done) {
      return { value, done };
    };
  }
});

// node_modules/core-js-pure/modules/es.array.iterator.js
var require_es_array_iterator = __commonJS({
  "node_modules/core-js-pure/modules/es.array.iterator.js"(exports, module) {
    "use strict";
    var toIndexedObject = require_to_indexed_object();
    var addToUnscopables = require_add_to_unscopables();
    var Iterators = require_iterators();
    var InternalStateModule = require_internal_state();
    var defineProperty = require_object_define_property().f;
    var defineIterator = require_iterator_define();
    var createIterResultObject = require_create_iter_result_object();
    var IS_PURE = require_is_pure();
    var DESCRIPTORS = require_descriptors();
    var ARRAY_ITERATOR = "Array Iterator";
    var setInternalState = InternalStateModule.set;
    var getInternalState = InternalStateModule.getterFor(ARRAY_ITERATOR);
    module.exports = defineIterator(Array, "Array", function(iterated, kind) {
      setInternalState(this, {
        type: ARRAY_ITERATOR,
        target: toIndexedObject(iterated),
        // target
        index: 0,
        // next index
        kind
        // kind
      });
    }, function() {
      var state = getInternalState(this);
      var target = state.target;
      var index = state.index++;
      if (!target || index >= target.length) {
        state.target = null;
        return createIterResultObject(void 0, true);
      }
      switch (state.kind) {
        case "keys":
          return createIterResultObject(index, false);
        case "values":
          return createIterResultObject(target[index], false);
      }
      return createIterResultObject([index, target[index]], false);
    }, "values");
    var values = Iterators.Arguments = Iterators.Array;
    addToUnscopables("keys");
    addToUnscopables("values");
    addToUnscopables("entries");
    if (!IS_PURE && DESCRIPTORS && values.name !== "values") try {
      defineProperty(values, "name", { value: "values" });
    } catch (error) {
    }
  }
});

// node_modules/core-js-pure/internals/safe-get-built-in.js
var require_safe_get_built_in = __commonJS({
  "node_modules/core-js-pure/internals/safe-get-built-in.js"(exports, module) {
    "use strict";
    var globalThis2 = require_global_this();
    var DESCRIPTORS = require_descriptors();
    var getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
    module.exports = function(name) {
      if (!DESCRIPTORS) return globalThis2[name];
      var descriptor = getOwnPropertyDescriptor(globalThis2, name);
      return descriptor && descriptor.value;
    };
  }
});

// node_modules/core-js-pure/internals/url-constructor-detection.js
var require_url_constructor_detection = __commonJS({
  "node_modules/core-js-pure/internals/url-constructor-detection.js"(exports, module) {
    "use strict";
    var fails = require_fails();
    var wellKnownSymbol = require_well_known_symbol();
    var DESCRIPTORS = require_descriptors();
    var IS_PURE = require_is_pure();
    var ITERATOR = wellKnownSymbol("iterator");
    module.exports = !fails(function() {
      var url = new URL("b?a=1&b=2&c=3", "https://a");
      var params = url.searchParams;
      var params2 = new URLSearchParams("a=1&a=2&b=3");
      var result = "";
      url.pathname = "c%20d";
      params.forEach(function(value, key2) {
        params["delete"]("b");
        result += key2 + value;
      });
      params2["delete"]("a", 2);
      params2["delete"]("b", void 0);
      return IS_PURE && (!url.toJSON || !params2.has("a", 1) || params2.has("a", 2) || !params2.has("a", void 0) || params2.has("b")) || !params.size && (IS_PURE || !DESCRIPTORS) || !params.sort || url.href !== "https://a/c%20d?a=1&c=3" || params.get("c") !== "3" || String(new URLSearchParams("?a=1")) !== "a=1" || !params[ITERATOR] || new URL("https://a@b").username !== "a" || new URLSearchParams(new URLSearchParams("a=b")).get("a") !== "b" || new URL("https://\u0442\u0435\u0441\u0442").host !== "xn--e1aybc" || new URL("https://a#\u0431").hash !== "#%D0%B1" || result !== "a1c3" || new URL("https://x", void 0).host !== "x";
    });
  }
});

// node_modules/core-js-pure/modules/es.string.from-code-point.js
var require_es_string_from_code_point = __commonJS({
  "node_modules/core-js-pure/modules/es.string.from-code-point.js"() {
    "use strict";
    var $ = require_export();
    var uncurryThis = require_function_uncurry_this();
    var toAbsoluteIndex = require_to_absolute_index();
    var $RangeError = RangeError;
    var fromCharCode = String.fromCharCode;
    var $fromCodePoint = String.fromCodePoint;
    var join = uncurryThis([].join);
    var INCORRECT_LENGTH = !!$fromCodePoint && $fromCodePoint.length !== 1;
    $({ target: "String", stat: true, arity: 1, forced: INCORRECT_LENGTH }, {
      // eslint-disable-next-line no-unused-vars -- required for `.length`
      fromCodePoint: function fromCodePoint(x) {
        var elements = [];
        var length = arguments.length;
        var i = 0;
        var code;
        while (length > i) {
          code = +arguments[i];
          if (toAbsoluteIndex(code, 1114111) !== code) throw new $RangeError(code + " is not a valid code point");
          elements[i++] = code < 65536 ? fromCharCode(code) : fromCharCode(((code -= 65536) >> 10) + 55296, code % 1024 + 56320);
        }
        return join(elements, "");
      }
    });
  }
});

// node_modules/core-js-pure/internals/url-percent-coding.js
var require_url_percent_coding = __commonJS({
  "node_modules/core-js-pure/internals/url-percent-coding.js"(exports, module) {
    "use strict";
    require_es_string_from_code_point();
    var getBuiltIn = require_get_built_in();
    var uncurryThis = require_function_uncurry_this();
    var fromCharCode = String.fromCharCode;
    var fromCodePoint = getBuiltIn("String", "fromCodePoint");
    var $encodeURIComponent = encodeURIComponent;
    var $parseInt = parseInt;
    var charAt = uncurryThis("".charAt);
    var push = uncurryThis([].push);
    var replace = uncurryThis("".replace);
    var stringSlice = uncurryThis("".slice);
    var exec = uncurryThis(/./.exec);
    var FALLBACK_REPLACER = "\uFFFD";
    var VALID_HEX = /^[0-9a-f]+$/i;
    var SURROGATE = /[\uD800-\uDBFF][\uDC00-\uDFFF]|[\uD800-\uDFFF]/g;
    var parseHexOctet = function(string, start) {
      var substr = stringSlice(string, start, start + 2);
      if (!exec(VALID_HEX, substr)) return NaN;
      return $parseInt(substr, 16);
    };
    var getLeadingOnes = function(octet) {
      var count = 0;
      for (var mask = 128; mask > 0 && (octet & mask) !== 0; mask >>= 1) {
        count++;
      }
      return count;
    };
    var utf8Decode = function(octets) {
      var codePoint = null;
      var length = octets.length;
      switch (length) {
        case 1:
          codePoint = octets[0];
          break;
        case 2:
          codePoint = (octets[0] & 31) << 6 | octets[1] & 63;
          break;
        case 3:
          codePoint = (octets[0] & 15) << 12 | (octets[1] & 63) << 6 | octets[2] & 63;
          break;
        case 4:
          codePoint = (octets[0] & 7) << 18 | (octets[1] & 63) << 12 | (octets[2] & 63) << 6 | octets[3] & 63;
          break;
      }
      if (codePoint === null || codePoint > 1114111 || codePoint >= 55296 && codePoint <= 57343 || codePoint < (length > 3 ? 65536 : length > 2 ? 2048 : length > 1 ? 128 : 0)) return null;
      return codePoint;
    };
    var replaceLoneSurrogate = function(chunk) {
      return chunk.length === 2 ? chunk : FALLBACK_REPLACER;
    };
    var decode = function(input) {
      var length = input.length;
      var result = "";
      var i = 0;
      while (i < length) {
        var decodedChar = charAt(input, i);
        if (decodedChar === "%") {
          if (charAt(input, i + 1) === "%" || i + 3 > length) {
            result += "%";
            i++;
            continue;
          }
          var octet = parseHexOctet(input, i + 1);
          if (octet !== octet) {
            result += decodedChar;
            i++;
            continue;
          }
          i += 2;
          var byteSequenceLength = getLeadingOnes(octet);
          if (byteSequenceLength === 0) {
            decodedChar = fromCharCode(octet);
          } else {
            if (byteSequenceLength === 1 || byteSequenceLength > 4) {
              result += FALLBACK_REPLACER;
              i++;
              continue;
            }
            var octets = [octet];
            var sequenceIndex = 1;
            while (sequenceIndex < byteSequenceLength) {
              i++;
              if (i + 3 > length || charAt(input, i) !== "%") break;
              var nextByte = parseHexOctet(input, i + 1);
              if (nextByte !== nextByte || nextByte > 191 || nextByte < 128) break;
              if (sequenceIndex === 1) {
                if (octet === 224 && nextByte < 160) break;
                if (octet === 237 && nextByte > 159) break;
                if (octet === 240 && nextByte < 144) break;
                if (octet === 244 && nextByte > 143) break;
              }
              push(octets, nextByte);
              i += 2;
              sequenceIndex++;
            }
            if (octets.length !== byteSequenceLength) {
              result += FALLBACK_REPLACER;
              continue;
            }
            var codePoint = utf8Decode(octets);
            if (codePoint === null) {
              for (var replacement = 0; replacement < byteSequenceLength; replacement++) result += FALLBACK_REPLACER;
              i++;
              continue;
            } else {
              decodedChar = fromCodePoint(codePoint);
            }
          }
        }
        result += decodedChar;
        i++;
      }
      return result;
    };
    var encode = function(input) {
      try {
        return $encodeURIComponent(input);
      } catch (error) {
        return $encodeURIComponent(replace(input, SURROGATE, replaceLoneSurrogate));
      }
    };
    module.exports = {
      decode,
      encode
    };
  }
});

// node_modules/core-js-pure/internals/define-built-ins.js
var require_define_built_ins = __commonJS({
  "node_modules/core-js-pure/internals/define-built-ins.js"(exports, module) {
    "use strict";
    var defineBuiltIn = require_define_built_in();
    module.exports = function(target, src, options) {
      for (var key2 in src) {
        if (options && options.unsafe && target[key2]) target[key2] = src[key2];
        else defineBuiltIn(target, key2, src[key2], options);
      }
      return target;
    };
  }
});

// node_modules/core-js-pure/internals/get-internal-iterator.js
var require_get_internal_iterator = __commonJS({
  "node_modules/core-js-pure/internals/get-internal-iterator.js"(exports, module) {
    "use strict";
    var classof = require_classof();
    var hasOwn = require_has_own_property();
    var Iterators = require_iterators();
    module.exports = function(it) {
      var klass = classof(it);
      if (klass === "Arguments") klass = "Array";
      return hasOwn(Iterators, klass) ? Iterators[klass] : void 0;
    };
  }
});

// node_modules/core-js-pure/internals/get-iterator-method-internal.js
var require_get_iterator_method_internal = __commonJS({
  "node_modules/core-js-pure/internals/get-iterator-method-internal.js"(exports, module) {
    "use strict";
    var getMethod = require_get_method();
    var isNullOrUndefined = require_is_null_or_undefined();
    var getInternalIterator = require_get_internal_iterator();
    var wellKnownSymbol = require_well_known_symbol();
    var ITERATOR = wellKnownSymbol("iterator");
    module.exports = function(it) {
      if (!isNullOrUndefined(it)) return getMethod(it, ITERATOR) || getMethod(it, "@@iterator") || getInternalIterator(it);
    };
  }
});

// node_modules/core-js-pure/internals/get-iterator-internal.js
var require_get_iterator_internal = __commonJS({
  "node_modules/core-js-pure/internals/get-iterator-internal.js"(exports, module) {
    "use strict";
    var call = require_function_call();
    var isCallable = require_is_callable();
    var anObject = require_an_object();
    var tryToString = require_try_to_string();
    var getIteratorMethod = require_get_iterator_method_internal();
    var $TypeError = TypeError;
    module.exports = function(argument, usingIterator) {
      var iteratorMethod = arguments.length < 2 ? getIteratorMethod(argument) : usingIterator;
      if (isCallable(iteratorMethod)) return anObject(call(iteratorMethod, argument));
      throw new $TypeError(tryToString(argument) + " is not iterable");
    };
  }
});

// node_modules/core-js-pure/internals/array-slice.js
var require_array_slice = __commonJS({
  "node_modules/core-js-pure/internals/array-slice.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this();
    module.exports = uncurryThis([].slice);
  }
});

// node_modules/core-js-pure/internals/array-sort.js
var require_array_sort = __commonJS({
  "node_modules/core-js-pure/internals/array-sort.js"(exports, module) {
    "use strict";
    var arraySlice = require_array_slice();
    var floor = Math.floor;
    var sort = function(array, comparefn) {
      var length = array.length;
      if (length < 8) {
        var i = 1;
        var element, j;
        while (i < length) {
          j = i;
          element = array[i];
          while (j && comparefn(array[j - 1], element) > 0) {
            array[j] = array[--j];
          }
          if (j !== i++) array[j] = element;
        }
      } else {
        var middle = floor(length / 2);
        var left = sort(arraySlice(array, 0, middle), comparefn);
        var right = sort(arraySlice(array, middle), comparefn);
        var llength = left.length;
        var rlength = right.length;
        var lindex = 0;
        var rindex = 0;
        while (lindex < llength || rindex < rlength) {
          array[lindex + rindex] = lindex < llength && rindex < rlength ? comparefn(left[lindex], right[rindex]) <= 0 ? left[lindex++] : right[rindex++] : lindex < llength ? left[lindex++] : right[rindex++];
        }
      }
      return array;
    };
    module.exports = sort;
  }
});

// node_modules/core-js-pure/modules/web.url-search-params.constructor.js
var require_web_url_search_params_constructor = __commonJS({
  "node_modules/core-js-pure/modules/web.url-search-params.constructor.js"(exports, module) {
    "use strict";
    require_es_array_iterator();
    var $ = require_export();
    var globalThis2 = require_global_this();
    var safeGetBuiltIn = require_safe_get_built_in();
    var call = require_function_call();
    var uncurryThis = require_function_uncurry_this();
    var DESCRIPTORS = require_descriptors();
    var USE_NATIVE_URL = require_url_constructor_detection();
    var percentCoding = require_url_percent_coding();
    var defineBuiltIn = require_define_built_in();
    var defineBuiltInAccessor = require_define_built_in_accessor();
    var defineBuiltIns = require_define_built_ins();
    var setToStringTag = require_set_to_string_tag();
    var createIteratorConstructor = require_iterator_create_constructor();
    var InternalStateModule = require_internal_state();
    var anInstance = require_an_instance();
    var isCallable = require_is_callable();
    var hasOwn = require_has_own_property();
    var bind = require_function_bind_context();
    var classof = require_classof();
    var anObject = require_an_object();
    var isObject = require_is_object();
    var $toString = require_to_string();
    var create = require_object_create();
    var createPropertyDescriptor = require_create_property_descriptor();
    var getIterator = require_get_iterator_internal();
    var getIteratorMethod = require_get_iterator_method_internal();
    var createIterResultObject = require_create_iter_result_object();
    var validateArgumentsLength = require_validate_arguments_length();
    var wellKnownSymbol = require_well_known_symbol();
    var arraySort = require_array_sort();
    var ITERATOR = wellKnownSymbol("iterator");
    var URL_SEARCH_PARAMS = "URLSearchParams";
    var URL_SEARCH_PARAMS_ITERATOR = URL_SEARCH_PARAMS + "Iterator";
    var setInternalState = InternalStateModule.set;
    var getInternalParamsState = InternalStateModule.getterFor(URL_SEARCH_PARAMS);
    var getInternalIteratorState = InternalStateModule.getterFor(URL_SEARCH_PARAMS_ITERATOR);
    var percentDecode = percentCoding.decode;
    var percentEncode = percentCoding.encode;
    var nativeFetch = safeGetBuiltIn("fetch");
    var NativeRequest = safeGetBuiltIn("Request");
    var Headers = safeGetBuiltIn("Headers");
    var RequestPrototype = NativeRequest && NativeRequest.prototype;
    var HeadersPrototype = Headers && Headers.prototype;
    var TypeError2 = globalThis2.TypeError;
    var charAt = uncurryThis("".charAt);
    var join = uncurryThis([].join);
    var push = uncurryThis([].push);
    var replace = uncurryThis("".replace);
    var shift = uncurryThis([].shift);
    var splice = uncurryThis([].splice);
    var split = uncurryThis("".split);
    var stringSlice = uncurryThis("".slice);
    var plus = /\+/g;
    var decodeQueryComponent = function(input) {
      return percentDecode(replace(input, plus, " "));
    };
    var find = /[!'()~]|%20/g;
    var replacements = {
      "!": "%21",
      "'": "%27",
      "(": "%28",
      ")": "%29",
      "~": "%7E",
      "%20": "+"
    };
    var replacer = function(match) {
      return replacements[match];
    };
    var serialize = function(it) {
      return replace(percentEncode(it), find, replacer);
    };
    var URLSearchParamsIterator = createIteratorConstructor(function Iterator(params, kind) {
      setInternalState(this, {
        type: URL_SEARCH_PARAMS_ITERATOR,
        target: getInternalParamsState(params).entries,
        index: 0,
        kind
      });
    }, URL_SEARCH_PARAMS, function next() {
      var state = getInternalIteratorState(this);
      var target = state.target;
      var index = state.index++;
      if (!target || index >= target.length) {
        state.target = null;
        return createIterResultObject(void 0, true);
      }
      var entry = target[index];
      switch (state.kind) {
        case "keys":
          return createIterResultObject(entry.key, false);
        case "values":
          return createIterResultObject(entry.value, false);
      }
      return createIterResultObject([entry.key, entry.value], false);
    }, true);
    var URLSearchParamsState = function(init) {
      this.entries = [];
      this.url = null;
      if (init !== void 0) {
        if (isObject(init)) this.parseObject(init);
        else this.parseQuery(typeof init == "string" ? charAt(init, 0) === "?" ? stringSlice(init, 1) : init : $toString(init));
      }
    };
    URLSearchParamsState.prototype = {
      type: URL_SEARCH_PARAMS,
      bindURL: function(url) {
        this.url = url;
        this.update();
      },
      parseObject: function(object4) {
        var entries = this.entries;
        var iteratorMethod = getIteratorMethod(object4);
        var iterator, next, step, entryIterator, entryNext, first, second;
        if (iteratorMethod) {
          iterator = getIterator(object4, iteratorMethod);
          next = iterator.next;
          while (!(step = call(next, iterator)).done) {
            entryIterator = getIterator(anObject(step.value));
            entryNext = entryIterator.next;
            if ((first = call(entryNext, entryIterator)).done || (second = call(entryNext, entryIterator)).done || !call(entryNext, entryIterator).done) throw new TypeError2("Expected sequence with length 2");
            push(entries, { key: $toString(first.value), value: $toString(second.value) });
          }
        } else for (var key2 in object4) if (hasOwn(object4, key2)) {
          push(entries, { key: key2, value: $toString(object4[key2]) });
        }
      },
      parseQuery: function(query) {
        if (query) {
          var entries = this.entries;
          var attributes = split(query, "&");
          var index = 0;
          var attribute, entry;
          while (index < attributes.length) {
            attribute = attributes[index++];
            if (attribute.length) {
              entry = split(attribute, "=");
              push(entries, {
                key: decodeQueryComponent(shift(entry)),
                value: decodeQueryComponent(join(entry, "="))
              });
            }
          }
        }
      },
      serialize: function() {
        var entries = this.entries;
        var result = [];
        var index = 0;
        var entry;
        while (index < entries.length) {
          entry = entries[index++];
          push(result, serialize(entry.key) + "=" + serialize(entry.value));
        }
        return join(result, "&");
      },
      update: function() {
        this.entries.length = 0;
        this.parseQuery(this.url.query);
      },
      updateURL: function() {
        if (this.url) this.url.update();
      }
    };
    var URLSearchParamsConstructor = function URLSearchParams2() {
      anInstance(this, URLSearchParamsPrototype);
      var init = arguments.length > 0 ? arguments[0] : void 0;
      var state = setInternalState(this, new URLSearchParamsState(init));
      if (!DESCRIPTORS) this.size = state.entries.length;
    };
    var URLSearchParamsPrototype = URLSearchParamsConstructor.prototype;
    defineBuiltIns(URLSearchParamsPrototype, {
      // `URLSearchParams.prototype.append` method
      // https://url.spec.whatwg.org/#dom-urlsearchparams-append
      append: function append(name, value) {
        var state = getInternalParamsState(this);
        validateArgumentsLength(arguments.length, 2);
        push(state.entries, { key: $toString(name), value: $toString(value) });
        if (!DESCRIPTORS) this.size++;
        state.updateURL();
      },
      // `URLSearchParams.prototype.delete` method
      // https://url.spec.whatwg.org/#dom-urlsearchparams-delete
      "delete": function(name) {
        var state = getInternalParamsState(this);
        var length = validateArgumentsLength(arguments.length, 1);
        var entries = state.entries;
        var key2 = $toString(name);
        var $value = length < 2 ? void 0 : arguments[1];
        var value = $value === void 0 ? $value : $toString($value);
        var index = 0;
        while (index < entries.length) {
          var entry = entries[index];
          if (entry.key === key2 && (value === void 0 || entry.value === value)) {
            splice(entries, index, 1);
          } else index++;
        }
        if (!DESCRIPTORS) this.size = entries.length;
        state.updateURL();
      },
      // `URLSearchParams.prototype.get` method
      // https://url.spec.whatwg.org/#dom-urlsearchparams-get
      get: function get(name) {
        var entries = getInternalParamsState(this).entries;
        validateArgumentsLength(arguments.length, 1);
        var key2 = $toString(name);
        var index = 0;
        for (; index < entries.length; index++) {
          if (entries[index].key === key2) return entries[index].value;
        }
        return null;
      },
      // `URLSearchParams.prototype.getAll` method
      // https://url.spec.whatwg.org/#dom-urlsearchparams-getall
      getAll: function getAll(name) {
        var entries = getInternalParamsState(this).entries;
        validateArgumentsLength(arguments.length, 1);
        var key2 = $toString(name);
        var result = [];
        var index = 0;
        for (; index < entries.length; index++) {
          if (entries[index].key === key2) push(result, entries[index].value);
        }
        return result;
      },
      // `URLSearchParams.prototype.has` method
      // https://url.spec.whatwg.org/#dom-urlsearchparams-has
      has: function has(name) {
        var entries = getInternalParamsState(this).entries;
        var length = validateArgumentsLength(arguments.length, 1);
        var key2 = $toString(name);
        var $value = length < 2 ? void 0 : arguments[1];
        var value = $value === void 0 ? $value : $toString($value);
        var index = 0;
        while (index < entries.length) {
          var entry = entries[index++];
          if (entry.key === key2 && (value === void 0 || entry.value === value)) return true;
        }
        return false;
      },
      // `URLSearchParams.prototype.set` method
      // https://url.spec.whatwg.org/#dom-urlsearchparams-set
      set: function set(name, value) {
        var state = getInternalParamsState(this);
        validateArgumentsLength(arguments.length, 2);
        var entries = state.entries;
        var found = false;
        var key2 = $toString(name);
        var val = $toString(value);
        var index = 0;
        var entry;
        for (; index < entries.length; index++) {
          entry = entries[index];
          if (entry.key === key2) {
            if (found) splice(entries, index--, 1);
            else {
              found = true;
              entry.value = val;
            }
          }
        }
        if (!found) push(entries, { key: key2, value: val });
        if (!DESCRIPTORS) this.size = entries.length;
        state.updateURL();
      },
      // `URLSearchParams.prototype.sort` method
      // https://url.spec.whatwg.org/#dom-urlsearchparams-sort
      sort: function sort() {
        var state = getInternalParamsState(this);
        arraySort(state.entries, function(a, b) {
          return a.key > b.key ? 1 : -1;
        });
        state.updateURL();
      },
      // `URLSearchParams.prototype.forEach` method
      forEach: function forEach(callback) {
        var entries = getInternalParamsState(this).entries;
        var boundFunction = bind(callback, arguments.length > 1 ? arguments[1] : void 0);
        var index = 0;
        var entry;
        while (index < entries.length) {
          entry = entries[index++];
          boundFunction(entry.value, entry.key, this);
        }
      },
      // `URLSearchParams.prototype.keys` method
      keys: function keys2() {
        return new URLSearchParamsIterator(this, "keys");
      },
      // `URLSearchParams.prototype.values` method
      values: function values() {
        return new URLSearchParamsIterator(this, "values");
      },
      // `URLSearchParams.prototype.entries` method
      entries: function entries() {
        return new URLSearchParamsIterator(this, "entries");
      }
    }, { enumerable: true });
    defineBuiltIn(URLSearchParamsPrototype, ITERATOR, URLSearchParamsPrototype.entries, { name: "entries" });
    defineBuiltIn(URLSearchParamsPrototype, "toString", function toString() {
      return getInternalParamsState(this).serialize();
    }, { enumerable: true });
    if (DESCRIPTORS) defineBuiltInAccessor(URLSearchParamsPrototype, "size", {
      get: function size() {
        return getInternalParamsState(this).entries.length;
      },
      configurable: true,
      enumerable: true
    });
    setToStringTag(URLSearchParamsConstructor, URL_SEARCH_PARAMS);
    $({ global: true, constructor: true, forced: !USE_NATIVE_URL }, {
      URLSearchParams: URLSearchParamsConstructor
    });
    if (!USE_NATIVE_URL && isCallable(Headers)) {
      headersHas = uncurryThis(HeadersPrototype.has);
      headersSet = uncurryThis(HeadersPrototype.set);
      wrapRequestOptions = function(init) {
        if (isObject(init)) {
          var body = init.body;
          var headers;
          if (classof(body) === URL_SEARCH_PARAMS) {
            headers = init.headers ? new Headers(init.headers) : new Headers();
            if (!headersHas(headers, "content-type")) {
              headersSet(headers, "content-type", "application/x-www-form-urlencoded;charset=UTF-8");
            }
            return create(init, {
              body: createPropertyDescriptor(0, $toString(body)),
              headers: createPropertyDescriptor(0, headers)
            });
          }
        }
        return init;
      };
      if (isCallable(nativeFetch)) {
        $({ global: true, enumerable: true, dontCallGetSet: true, forced: true }, {
          fetch: function fetch(input) {
            return nativeFetch(input, arguments.length > 1 ? wrapRequestOptions(arguments[1]) : {});
          }
        });
      }
      if (isCallable(NativeRequest)) {
        RequestConstructor = function Request(input) {
          anInstance(this, RequestPrototype);
          return new NativeRequest(input, arguments.length > 1 ? wrapRequestOptions(arguments[1]) : {});
        };
        RequestPrototype.constructor = RequestConstructor;
        RequestConstructor.prototype = RequestPrototype;
        $({ global: true, constructor: true, dontCallGetSet: true, forced: true }, {
          Request: RequestConstructor
        });
      }
    }
    var headersHas;
    var headersSet;
    var wrapRequestOptions;
    var RequestConstructor;
    module.exports = {
      URLSearchParams: URLSearchParamsConstructor,
      getState: getInternalParamsState
    };
  }
});

// node_modules/core-js-pure/modules/web.url-search-params.js
var require_web_url_search_params = __commonJS({
  "node_modules/core-js-pure/modules/web.url-search-params.js"() {
    "use strict";
    require_web_url_search_params_constructor();
  }
});

// node_modules/core-js-pure/modules/web.url-search-params.delete.js
var require_web_url_search_params_delete = __commonJS({
  "node_modules/core-js-pure/modules/web.url-search-params.delete.js"() {
  }
});

// node_modules/core-js-pure/modules/web.url-search-params.has.js
var require_web_url_search_params_has = __commonJS({
  "node_modules/core-js-pure/modules/web.url-search-params.has.js"() {
  }
});

// node_modules/core-js-pure/modules/web.url-search-params.size.js
var require_web_url_search_params_size = __commonJS({
  "node_modules/core-js-pure/modules/web.url-search-params.size.js"() {
  }
});

// node_modules/core-js-pure/web/url-search-params.js
var require_url_search_params = __commonJS({
  "node_modules/core-js-pure/web/url-search-params.js"(exports, module) {
    "use strict";
    require_web_url_search_params();
    require_web_url_search_params_delete();
    require_web_url_search_params_has();
    require_web_url_search_params_size();
    var path = require_path();
    module.exports = path.URLSearchParams;
  }
});

// node_modules/core-js-pure/internals/string-multibyte.js
var require_string_multibyte = __commonJS({
  "node_modules/core-js-pure/internals/string-multibyte.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this();
    var toIntegerOrInfinity = require_to_integer_or_infinity();
    var toString = require_to_string();
    var requireObjectCoercible = require_require_object_coercible();
    var charAt = uncurryThis("".charAt);
    var charCodeAt = uncurryThis("".charCodeAt);
    var stringSlice = uncurryThis("".slice);
    var createMethod = function(CONVERT_TO_STRING) {
      return function($this, pos) {
        var S = toString(requireObjectCoercible($this));
        var position = toIntegerOrInfinity(pos);
        var size = S.length;
        var first, second;
        if (position < 0 || position >= size) return CONVERT_TO_STRING ? "" : void 0;
        first = charCodeAt(S, position);
        return first < 55296 || first > 56319 || position + 1 === size || (second = charCodeAt(S, position + 1)) < 56320 || second > 57343 ? CONVERT_TO_STRING ? charAt(S, position) : first : CONVERT_TO_STRING ? stringSlice(S, position, position + 2) : (first - 55296 << 10) + (second - 56320) + 65536;
      };
    };
    module.exports = {
      // `String.prototype.codePointAt` method
      // https://tc39.es/ecma262/#sec-string.prototype.codepointat
      codeAt: createMethod(false),
      // `String.prototype.at` method
      // https://github.com/mathiasbynens/String.prototype.at
      charAt: createMethod(true)
    };
  }
});

// node_modules/core-js-pure/modules/es.string.iterator.js
var require_es_string_iterator = __commonJS({
  "node_modules/core-js-pure/modules/es.string.iterator.js"() {
    "use strict";
    var charAt = require_string_multibyte().charAt;
    var toString = require_to_string();
    var InternalStateModule = require_internal_state();
    var defineIterator = require_iterator_define();
    var createIterResultObject = require_create_iter_result_object();
    var STRING_ITERATOR = "String Iterator";
    var setInternalState = InternalStateModule.set;
    var getInternalState = InternalStateModule.getterFor(STRING_ITERATOR);
    defineIterator(String, "String", function(iterated) {
      setInternalState(this, {
        type: STRING_ITERATOR,
        string: toString(iterated),
        index: 0
      });
    }, function next() {
      var state = getInternalState(this);
      var string = state.string;
      var index = state.index;
      var point;
      if (index >= string.length) return createIterResultObject(void 0, true);
      point = charAt(string, index);
      state.index += point.length;
      return createIterResultObject(point, false);
    });
  }
});

// node_modules/core-js-pure/internals/object-get-own-property-symbols.js
var require_object_get_own_property_symbols = __commonJS({
  "node_modules/core-js-pure/internals/object-get-own-property-symbols.js"(exports) {
    "use strict";
    exports.f = Object.getOwnPropertySymbols;
  }
});

// node_modules/core-js-pure/internals/object-assign.js
var require_object_assign = __commonJS({
  "node_modules/core-js-pure/internals/object-assign.js"(exports, module) {
    "use strict";
    var DESCRIPTORS = require_descriptors();
    var uncurryThis = require_function_uncurry_this();
    var call = require_function_call();
    var fails = require_fails();
    var objectKeys = require_object_keys();
    var getOwnPropertySymbolsModule = require_object_get_own_property_symbols();
    var propertyIsEnumerableModule = require_object_property_is_enumerable();
    var toObject = require_to_object();
    var IndexedObject = require_indexed_object();
    var $assign = Object.assign;
    var defineProperty = Object.defineProperty;
    var concat = uncurryThis([].concat);
    module.exports = !$assign || fails(function() {
      if (DESCRIPTORS && $assign({ b: 1 }, $assign(defineProperty({}, "a", {
        enumerable: true,
        get: function() {
          defineProperty(this, "b", {
            value: 3,
            enumerable: false
          });
        }
      }), { b: 2 })).b !== 1) return true;
      var A = {};
      var B = {};
      var symbol = Symbol("assign detection");
      var alphabet = "abcdefghijklmnopqrst";
      A[symbol] = 7;
      alphabet.split("").forEach(function(chr) {
        B[chr] = chr;
      });
      return $assign({}, A)[symbol] !== 7 || objectKeys($assign({}, B)).join("") !== alphabet;
    }) ? function assign(target, source) {
      var T = toObject(target);
      var argumentsLength = arguments.length;
      var index = 1;
      var getOwnPropertySymbols = getOwnPropertySymbolsModule.f;
      var propertyIsEnumerable = propertyIsEnumerableModule.f;
      while (argumentsLength > index) {
        var S = IndexedObject(arguments[index++]);
        var keys2 = getOwnPropertySymbols ? concat(objectKeys(S), getOwnPropertySymbols(S)) : objectKeys(S);
        var length = keys2.length;
        var j = 0;
        var key2;
        while (length > j) {
          key2 = keys2[j++];
          if (!DESCRIPTORS || call(propertyIsEnumerable, S, key2)) T[key2] = S[key2];
        }
      }
      return T;
    } : $assign;
  }
});

// node_modules/core-js-pure/internals/iterator-close.js
var require_iterator_close = __commonJS({
  "node_modules/core-js-pure/internals/iterator-close.js"(exports, module) {
    "use strict";
    var call = require_function_call();
    var anObject = require_an_object();
    var getMethod = require_get_method();
    module.exports = function(iterator, kind, value) {
      var innerResult, innerError;
      anObject(iterator);
      try {
        innerResult = getMethod(iterator, "return");
        if (!innerResult) {
          if (kind === "throw") throw value;
          return value;
        }
        innerResult = call(innerResult, iterator);
      } catch (error) {
        innerError = true;
        innerResult = error;
      }
      if (kind === "throw") throw value;
      if (innerError) throw innerResult;
      anObject(innerResult);
      return value;
    };
  }
});

// node_modules/core-js-pure/internals/call-with-safe-iteration-closing.js
var require_call_with_safe_iteration_closing = __commonJS({
  "node_modules/core-js-pure/internals/call-with-safe-iteration-closing.js"(exports, module) {
    "use strict";
    var anObject = require_an_object();
    var iteratorClose = require_iterator_close();
    module.exports = function(iterator, fn, value, ENTRIES) {
      try {
        return ENTRIES ? fn(anObject(value)[0], value[1]) : fn(value);
      } catch (error) {
        iteratorClose(iterator, "throw", error);
      }
    };
  }
});

// node_modules/core-js-pure/internals/is-array-iterator-method.js
var require_is_array_iterator_method = __commonJS({
  "node_modules/core-js-pure/internals/is-array-iterator-method.js"(exports, module) {
    "use strict";
    var wellKnownSymbol = require_well_known_symbol();
    var Iterators = require_iterators();
    var ITERATOR = wellKnownSymbol("iterator");
    var ArrayPrototype = Array.prototype;
    module.exports = function(it) {
      return it !== void 0 && (Iterators.Array === it || ArrayPrototype[ITERATOR] === it);
    };
  }
});

// node_modules/core-js-pure/internals/inspect-source.js
var require_inspect_source = __commonJS({
  "node_modules/core-js-pure/internals/inspect-source.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this();
    var isCallable = require_is_callable();
    var store = require_shared_store();
    var functionToString = uncurryThis(Function.toString);
    if (!isCallable(store.inspectSource)) {
      store.inspectSource = function(it) {
        return functionToString(it);
      };
    }
    module.exports = store.inspectSource;
  }
});

// node_modules/core-js-pure/internals/is-constructor.js
var require_is_constructor = __commonJS({
  "node_modules/core-js-pure/internals/is-constructor.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this();
    var fails = require_fails();
    var isCallable = require_is_callable();
    var classof = require_classof();
    var getBuiltIn = require_get_built_in();
    var inspectSource = require_inspect_source();
    var noop = function() {
    };
    var construct = getBuiltIn("Reflect", "construct");
    var constructorRegExp = /^\s*(?:class|function)\b/;
    var exec = uncurryThis(constructorRegExp.exec);
    var INCORRECT_TO_STRING = !constructorRegExp.test(noop);
    var isConstructorModern = function isConstructor(argument) {
      if (!isCallable(argument)) return false;
      try {
        construct(noop, [], argument);
        return true;
      } catch (error) {
        return false;
      }
    };
    var isConstructorLegacy = function isConstructor(argument) {
      if (!isCallable(argument)) return false;
      switch (classof(argument)) {
        case "AsyncFunction":
        case "GeneratorFunction":
        case "AsyncGeneratorFunction":
          return false;
      }
      try {
        return INCORRECT_TO_STRING || !!exec(constructorRegExp, inspectSource(argument));
      } catch (error) {
        return true;
      }
    };
    isConstructorLegacy.sham = true;
    module.exports = !construct || fails(function() {
      var called;
      return isConstructorModern(isConstructorModern.call) || !isConstructorModern(Object) || !isConstructorModern(function() {
        called = true;
      }) || called;
    }) ? isConstructorLegacy : isConstructorModern;
  }
});

// node_modules/core-js-pure/internals/create-property.js
var require_create_property = __commonJS({
  "node_modules/core-js-pure/internals/create-property.js"(exports, module) {
    "use strict";
    var DESCRIPTORS = require_descriptors();
    var definePropertyModule = require_object_define_property();
    var createPropertyDescriptor = require_create_property_descriptor();
    module.exports = function(object4, key2, value) {
      if (DESCRIPTORS) definePropertyModule.f(object4, key2, createPropertyDescriptor(0, value));
      else object4[key2] = value;
    };
  }
});

// node_modules/core-js-pure/internals/is-array.js
var require_is_array = __commonJS({
  "node_modules/core-js-pure/internals/is-array.js"(exports, module) {
    "use strict";
    var classof = require_classof_raw();
    module.exports = Array.isArray || function isArray(argument) {
      return classof(argument) === "Array";
    };
  }
});

// node_modules/core-js-pure/internals/array-set-length.js
var require_array_set_length = __commonJS({
  "node_modules/core-js-pure/internals/array-set-length.js"(exports, module) {
    "use strict";
    var DESCRIPTORS = require_descriptors();
    var isArray = require_is_array();
    var $TypeError = TypeError;
    var getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
    var SILENT_ON_NON_WRITABLE_LENGTH_SET = DESCRIPTORS && !(function() {
      if (this !== void 0) return true;
      try {
        Object.defineProperty([], "length", { writable: false }).length = 1;
      } catch (error) {
        return error instanceof TypeError;
      }
    })();
    module.exports = SILENT_ON_NON_WRITABLE_LENGTH_SET ? function(O, length) {
      if (isArray(O) && !getOwnPropertyDescriptor(O, "length").writable) {
        throw new $TypeError("Cannot set read only .length");
      }
      return O.length = length;
    } : function(O, length) {
      return O.length = length;
    };
  }
});

// node_modules/core-js-pure/internals/does-not-exceed-safe-integer.js
var require_does_not_exceed_safe_integer = __commonJS({
  "node_modules/core-js-pure/internals/does-not-exceed-safe-integer.js"(exports, module) {
    "use strict";
    var $TypeError = TypeError;
    var MAX_SAFE_INTEGER = 9007199254740991;
    module.exports = function(it) {
      if (it > MAX_SAFE_INTEGER) throw new $TypeError("Maximum allowed index exceeded");
      return it;
    };
  }
});

// node_modules/core-js-pure/internals/array-from.js
var require_array_from = __commonJS({
  "node_modules/core-js-pure/internals/array-from.js"(exports, module) {
    "use strict";
    var bind = require_function_bind_context();
    var call = require_function_call();
    var toObject = require_to_object();
    var callWithSafeIterationClosing = require_call_with_safe_iteration_closing();
    var isArrayIteratorMethod = require_is_array_iterator_method();
    var isConstructor = require_is_constructor();
    var lengthOfArrayLike = require_length_of_array_like();
    var createProperty = require_create_property();
    var setArrayLength = require_array_set_length();
    var getIterator = require_get_iterator_internal();
    var getIteratorMethod = require_get_iterator_method_internal();
    var iteratorClose = require_iterator_close();
    var doesNotExceedSafeInteger = require_does_not_exceed_safe_integer();
    var $Array = Array;
    module.exports = function from(arrayLike) {
      var IS_CONSTRUCTOR = isConstructor(this);
      var argumentsLength = arguments.length;
      var mapfn = argumentsLength > 1 ? arguments[1] : void 0;
      var mapping = mapfn !== void 0;
      if (mapping) mapfn = bind(mapfn, argumentsLength > 2 ? arguments[2] : void 0);
      var O = toObject(arrayLike);
      var iteratorMethod = getIteratorMethod(O);
      var index = 0;
      var length, result, step, iterator, next, value;
      if (iteratorMethod && !(this === $Array && isArrayIteratorMethod(iteratorMethod))) {
        result = IS_CONSTRUCTOR ? new this() : [];
        iterator = getIterator(O, iteratorMethod);
        next = iterator.next;
        for (; !(step = call(next, iterator)).done; index++) {
          try {
            doesNotExceedSafeInteger(index);
          } catch (error) {
            iteratorClose(iterator, "throw", error);
          }
          value = mapping ? callWithSafeIterationClosing(iterator, mapfn, [step.value, index], true) : step.value;
          try {
            createProperty(result, index, value);
          } catch (error) {
            iteratorClose(iterator, "throw", error);
          }
        }
      } else {
        length = lengthOfArrayLike(O);
        result = IS_CONSTRUCTOR ? new this(length) : $Array(length);
        for (; length > index; index++) {
          value = mapping ? mapfn(O[index], index) : O[index];
          createProperty(result, index, value);
        }
      }
      setArrayLength(result, index);
      return result;
    };
  }
});

// node_modules/core-js-pure/internals/string-punycode-to-ascii.js
var require_string_punycode_to_ascii = __commonJS({
  "node_modules/core-js-pure/internals/string-punycode-to-ascii.js"(exports, module) {
    "use strict";
    var uncurryThis = require_function_uncurry_this();
    var maxInt = 2147483647;
    var base = 36;
    var tMin = 1;
    var tMax = 26;
    var skew = 38;
    var damp = 700;
    var initialBias = 72;
    var initialN = 128;
    var delimiter = "-";
    var regexNonASCII = /[^\0-\u007E]/;
    var regexSeparators = /[.\u3002\uFF0E\uFF61]/g;
    var OVERFLOW_ERROR = "Overflow: input needs wider integers to process";
    var baseMinusTMin = base - tMin;
    var $RangeError = RangeError;
    var exec = uncurryThis(regexSeparators.exec);
    var floor = Math.floor;
    var fromCharCode = String.fromCharCode;
    var charCodeAt = uncurryThis("".charCodeAt);
    var join = uncurryThis([].join);
    var push = uncurryThis([].push);
    var replace = uncurryThis("".replace);
    var split = uncurryThis("".split);
    var toLowerCase = uncurryThis("".toLowerCase);
    var ucs2decode = function(string) {
      var output = [];
      var counter = 0;
      var length = string.length;
      while (counter < length) {
        var value = charCodeAt(string, counter++);
        if (value >= 55296 && value <= 56319 && counter < length) {
          var extra = charCodeAt(string, counter++);
          if ((extra & 64512) === 56320) {
            push(output, ((value & 1023) << 10) + (extra & 1023) + 65536);
          } else {
            push(output, value);
            counter--;
          }
        } else {
          push(output, value);
        }
      }
      return output;
    };
    var digitToBasic = function(digit) {
      return digit + 22 + 75 * (digit < 26);
    };
    var adapt = function(delta, numPoints, firstTime) {
      var k = 0;
      delta = firstTime ? floor(delta / damp) : delta >> 1;
      delta += floor(delta / numPoints);
      while (delta > baseMinusTMin * tMax >> 1) {
        delta = floor(delta / baseMinusTMin);
        k += base;
      }
      return floor(k + (baseMinusTMin + 1) * delta / (delta + skew));
    };
    var encode = function(input) {
      var output = [];
      input = ucs2decode(input);
      var inputLength = input.length;
      var n = initialN;
      var delta = 0;
      var bias = initialBias;
      var i, currentValue;
      for (i = 0; i < input.length; i++) {
        currentValue = input[i];
        if (currentValue < 128) {
          push(output, fromCharCode(currentValue));
        }
      }
      var basicLength = output.length;
      var handledCPCount = basicLength;
      if (basicLength) {
        push(output, delimiter);
      }
      while (handledCPCount < inputLength) {
        var m = maxInt;
        for (i = 0; i < input.length; i++) {
          currentValue = input[i];
          if (currentValue >= n && currentValue < m) {
            m = currentValue;
          }
        }
        var handledCPCountPlusOne = handledCPCount + 1;
        if (m - n > floor((maxInt - delta) / handledCPCountPlusOne)) {
          throw new $RangeError(OVERFLOW_ERROR);
        }
        delta += (m - n) * handledCPCountPlusOne;
        n = m;
        for (i = 0; i < input.length; i++) {
          currentValue = input[i];
          if (currentValue < n && ++delta > maxInt) {
            throw new $RangeError(OVERFLOW_ERROR);
          }
          if (currentValue === n) {
            var q = delta;
            var k = base;
            while (true) {
              var t = k <= bias ? tMin : k >= bias + tMax ? tMax : k - bias;
              if (q < t) break;
              var qMinusT = q - t;
              var baseMinusT = base - t;
              push(output, fromCharCode(digitToBasic(t + qMinusT % baseMinusT)));
              q = floor(qMinusT / baseMinusT);
              k += base;
            }
            push(output, fromCharCode(digitToBasic(q)));
            bias = adapt(delta, handledCPCountPlusOne, handledCPCount === basicLength);
            delta = 0;
            handledCPCount++;
          }
        }
        delta++;
        n++;
      }
      return join(output, "");
    };
    module.exports = function(input) {
      var encoded = [];
      var labels = split(replace(toLowerCase(input), regexSeparators, "."), ".");
      var i, label;
      for (i = 0; i < labels.length; i++) {
        label = labels[i];
        push(encoded, exec(regexNonASCII, label) ? "xn--" + encode(label) : label);
      }
      return join(encoded, ".");
    };
  }
});

// node_modules/core-js-pure/modules/web.url.constructor.js
var require_web_url_constructor = __commonJS({
  "node_modules/core-js-pure/modules/web.url.constructor.js"() {
    "use strict";
    require_es_string_iterator();
    var $ = require_export();
    var DESCRIPTORS = require_descriptors();
    var USE_NATIVE_URL = require_url_constructor_detection();
    var globalThis2 = require_global_this();
    var bind = require_function_bind_context();
    var uncurryThis = require_function_uncurry_this();
    var defineBuiltIn = require_define_built_in();
    var defineBuiltInAccessor = require_define_built_in_accessor();
    var anInstance = require_an_instance();
    var hasOwn = require_has_own_property();
    var assign = require_object_assign();
    var arrayFrom = require_array_from();
    var arraySlice = require_array_slice();
    var codeAt = require_string_multibyte().codeAt;
    var toASCII = require_string_punycode_to_ascii();
    var percentCoding = require_url_percent_coding();
    var $toString = require_to_string();
    var setToStringTag = require_set_to_string_tag();
    var validateArgumentsLength = require_validate_arguments_length();
    var URLSearchParamsModule = require_web_url_search_params_constructor();
    var InternalStateModule = require_internal_state();
    var setInternalState = InternalStateModule.set;
    var getInternalURLState = InternalStateModule.getterFor("URL");
    var URLSearchParams2 = URLSearchParamsModule.URLSearchParams;
    var getInternalSearchParamsState = URLSearchParamsModule.getState;
    var percentDecode = percentCoding.decode;
    var percentEncode = percentCoding.encode;
    var NativeURL = globalThis2.URL;
    var TypeError2 = globalThis2.TypeError;
    var parseInt2 = globalThis2.parseInt;
    var floor = Math.floor;
    var pow = Math.pow;
    var fromCharCode = String.fromCharCode;
    var charAt = uncurryThis("".charAt);
    var exec = uncurryThis(/./.exec);
    var join = uncurryThis([].join);
    var numberToString = uncurryThis(1.1.toString);
    var pop = uncurryThis([].pop);
    var push = uncurryThis([].push);
    var replace = uncurryThis("".replace);
    var shift = uncurryThis([].shift);
    var split = uncurryThis("".split);
    var stringIndexOf = uncurryThis("".indexOf);
    var stringSlice = uncurryThis("".slice);
    var toLowerCase = uncurryThis("".toLowerCase);
    var unshift = uncurryThis([].unshift);
    var INVALID_AUTHORITY = "Invalid authority";
    var INVALID_SCHEME = "Invalid scheme";
    var INVALID_HOST = "Invalid host";
    var INVALID_PORT = "Invalid port";
    var ALPHA = /[a-z]/i;
    var ALPHANUMERIC_PLUS_MINUS_DOT = /[\d+\-.a-z]/i;
    var DIGIT = /\d/;
    var HEX_START = /^0x/i;
    var OCT = /^[0-7]+$/;
    var DEC = /^\d+$/;
    var HEX = /^[\da-f]+$/i;
    var FORBIDDEN_DOMAIN_CODE_POINT = /[\u0000-\u0020#%/:<>?@[\\\]^|\u007F]/;
    var FORBIDDEN_HOST_CODE_POINT = /[\0\t\n\r #/:<>?@[\\\]^|]/;
    var LEADING_C0_CONTROL_OR_SPACE = /^[\u0000-\u0020]+/;
    var TRAILING_C0_CONTROL_OR_SPACE = /(^|[^\u0000-\u0020])[\u0000-\u0020]+$/;
    var TAB_AND_NEW_LINE = /[\t\n\r]/g;
    var NON_ASCII = /[^\u0000-\u007F]/;
    var MAPPED_ONTO_FORBIDDEN = "\xA8\xAF\xB4\xB8\u02D8\u02D9\u02DA\u02DB\u02DC\u02DD\u037A\u0384\u0385\u1FBD\u1FBF\u1FC0\u1FC1\u1FCD\u1FCE\u1FCF\u1FDD\u1FDE\u1FDF\u1FED\u1FEE\u1FFD\u1FFE\u2017\u203E\u2047\u2048\u2049\u2100\u2101\u2105\u2106\u2A74\u309B\u309C\uFC5E\uFC5F\uFC60\uFC61\uFC62\uFC63\uFDFA\uFDFB\uFE13\uFE16\uFE47\uFE48\uFE49\uFE4A\uFE4B\uFE4C\uFE55\uFE56\uFE5F\uFE64\uFE65\uFE68\uFE6A\uFE6B\uFE70\uFE72\uFE74\uFE76\uFE78\uFE7A\uFE7C\uFE7E\uFFE3";
    var EOF;
    var isIgnoredCodePoint = function(code) {
      return code === 173 || code === 847 || code === 8203 || code === 12644 || code === 65279 || code === 65440 || code >= 4447 && code <= 4448 || code >= 6068 && code <= 6069 || code >= 6155 && code <= 6159 || code >= 8288 && code <= 8292 || code >= 8298 && code <= 8303 || code >= 65024 && code <= 65039 || code >= 917760 && code <= 917999;
    };
    var isDisallowedCodePoint = function(code) {
      return code === 65533 || code >= 55296 && code <= 57343 || code >= 128 && code <= 159 || code >= 8206 && code <= 8207 || code >= 8232 && code <= 8233 || code >= 8234 && code <= 8238 || code >= 8293 && code <= 8297 || code >= 64976 && code <= 65007 || (code & 65534) === 65534 || code >= 57344 && code <= 63743 || code >= 983040 && code <= 1114109;
    };
    var mapCodePoint = function(code) {
      if (code >= 65281 && code <= 65374) return code - 65248;
      if (code === 160 || code === 5760 || code === 8239 || code === 8287 || code === 12288) return 32;
      if (code >= 8192 && code <= 8202) return 32;
      if (code <= 65535 && stringIndexOf(MAPPED_ONTO_FORBIDDEN, fromCharCode(code)) > -1) return 32;
      return code;
    };
    var domainToASCII = function(domain) {
      if (!exec(NON_ASCII, domain)) return domain === "" ? null : toASCII(domain);
      var codePoints = arrayFrom(domain);
      var result = "";
      var index, code, mapped;
      for (index = 0; index < codePoints.length; index++) {
        code = codeAt(codePoints[index], 0);
        if (isDisallowedCodePoint(code)) return null;
        if (isIgnoredCodePoint(code)) continue;
        mapped = mapCodePoint(code);
        result += mapped === code ? codePoints[index] : fromCharCode(mapped);
      }
      return result === "" ? null : toASCII(result);
    };
    var endsInNumber = function(input) {
      var parts = split(input, ".");
      var last, hexPart;
      if (parts[parts.length - 1] === "") {
        if (parts.length === 1) return false;
        parts.length--;
      }
      last = parts[parts.length - 1];
      if (exec(DEC, last)) return true;
      if (exec(HEX_START, last)) {
        hexPart = stringSlice(last, 2);
        return hexPart === "" || !!exec(HEX, hexPart);
      }
      return false;
    };
    var parseIPv4 = function(input) {
      var parts = split(input, ".");
      var partsLength, numbers, index, part2, radix, number, ipv4;
      if (parts.length && parts[parts.length - 1] === "") {
        parts.length--;
      }
      partsLength = parts.length;
      if (partsLength > 4) return null;
      numbers = [];
      for (index = 0; index < partsLength; index++) {
        part2 = parts[index];
        if (part2 === "") return null;
        radix = 10;
        if (part2.length > 1 && charAt(part2, 0) === "0") {
          radix = exec(HEX_START, part2) ? 16 : 8;
          part2 = stringSlice(part2, radix === 8 ? 1 : 2);
        }
        if (part2 === "") {
          number = 0;
        } else {
          if (!exec(radix === 10 ? DEC : radix === 8 ? OCT : HEX, part2)) return null;
          number = parseInt2(part2, radix);
        }
        push(numbers, number);
      }
      for (index = 0; index < partsLength; index++) {
        number = numbers[index];
        if (index === partsLength - 1) {
          if (number >= pow(256, 5 - partsLength)) return null;
        } else if (number > 255) return null;
      }
      ipv4 = pop(numbers);
      for (index = 0; index < numbers.length; index++) {
        ipv4 += numbers[index] * pow(256, 3 - index);
      }
      return ipv4;
    };
    var parseIPv6 = function(input) {
      var address = [0, 0, 0, 0, 0, 0, 0, 0];
      var pieceIndex = 0;
      var compress = null;
      var pointer = 0;
      var value, length, numbersSeen, ipv4Piece, number, swaps, swap;
      var chr = function() {
        return charAt(input, pointer);
      };
      if (chr() === ":") {
        if (charAt(input, 1) !== ":") return;
        pointer += 2;
        pieceIndex++;
        compress = pieceIndex;
      }
      while (chr()) {
        if (pieceIndex === 8) return;
        if (chr() === ":") {
          if (compress !== null) return;
          pointer++;
          pieceIndex++;
          compress = pieceIndex;
          continue;
        }
        value = length = 0;
        while (length < 4 && exec(HEX, chr())) {
          value = value * 16 + parseInt2(chr(), 16);
          pointer++;
          length++;
        }
        if (chr() === ".") {
          if (length === 0) return;
          pointer -= length;
          if (pieceIndex > 6) return;
          numbersSeen = 0;
          while (chr()) {
            ipv4Piece = null;
            if (numbersSeen > 0) {
              if (chr() === "." && numbersSeen < 4) pointer++;
              else return;
            }
            if (!exec(DIGIT, chr())) return;
            while (exec(DIGIT, chr())) {
              number = parseInt2(chr(), 10);
              if (ipv4Piece === null) ipv4Piece = number;
              else if (ipv4Piece === 0) return;
              else ipv4Piece = ipv4Piece * 10 + number;
              if (ipv4Piece > 255) return;
              pointer++;
            }
            address[pieceIndex] = address[pieceIndex] * 256 + ipv4Piece;
            numbersSeen++;
            if (numbersSeen === 2 || numbersSeen === 4) pieceIndex++;
          }
          if (numbersSeen !== 4) return;
          break;
        } else if (chr() === ":") {
          pointer++;
          if (!chr()) return;
        } else if (chr()) return;
        address[pieceIndex++] = value;
      }
      if (compress !== null) {
        swaps = pieceIndex - compress;
        pieceIndex = 7;
        while (pieceIndex !== 0 && swaps > 0) {
          swap = address[pieceIndex];
          address[pieceIndex--] = address[compress + swaps - 1];
          address[compress + --swaps] = swap;
        }
      } else if (pieceIndex !== 8) return;
      return address;
    };
    var findLongestZeroSequence = function(ipv6) {
      var maxIndex = null;
      var maxLength = 1;
      var currStart = null;
      var currLength = 0;
      var index = 0;
      for (; index < 8; index++) {
        if (ipv6[index] !== 0) {
          if (currLength > maxLength) {
            maxIndex = currStart;
            maxLength = currLength;
          }
          currStart = null;
          currLength = 0;
        } else {
          if (currStart === null) currStart = index;
          ++currLength;
        }
      }
      return currLength > maxLength ? currStart : maxIndex;
    };
    var serializeHost = function(host) {
      var result, index, compress, ignore0;
      if (typeof host == "number") {
        result = [];
        for (index = 0; index < 4; index++) {
          unshift(result, host % 256);
          host = floor(host / 256);
        }
        return join(result, ".");
      }
      if (typeof host == "object") {
        result = "";
        compress = findLongestZeroSequence(host);
        for (index = 0; index < 8; index++) {
          if (ignore0 && host[index] === 0) continue;
          if (ignore0) ignore0 = false;
          if (compress === index) {
            result += index ? ":" : "::";
            ignore0 = true;
          } else {
            result += numberToString(host[index], 16);
            if (index < 7) result += ":";
          }
        }
        return "[" + result + "]";
      }
      return host;
    };
    var C0ControlPercentEncodeSet = {};
    var queryPercentEncodeSet = assign({}, C0ControlPercentEncodeSet, {
      " ": 1,
      '"': 1,
      "#": 1,
      "<": 1,
      ">": 1
    });
    var specialQueryPercentEncodeSet = assign({}, queryPercentEncodeSet, {
      "'": 1
    });
    var fragmentPercentEncodeSet = assign({}, C0ControlPercentEncodeSet, {
      " ": 1,
      '"': 1,
      "<": 1,
      ">": 1,
      "`": 1
    });
    var pathPercentEncodeSet = assign({}, fragmentPercentEncodeSet, {
      "#": 1,
      "?": 1,
      "{": 1,
      "}": 1,
      "^": 1
    });
    var userinfoPercentEncodeSet = assign({}, pathPercentEncodeSet, {
      "/": 1,
      ":": 1,
      ";": 1,
      "=": 1,
      "@": 1,
      "[": 1,
      "\\": 1,
      "]": 1,
      "^": 1,
      "|": 1
    });
    var utf8PercentEncode = function(chr, set) {
      var code = codeAt(chr, 0);
      return code >= 32 && code < 127 && !hasOwn(set, chr) ? chr : chr === "'" && hasOwn(set, chr) ? "%27" : percentEncode(chr);
    };
    var specialSchemes = {
      ftp: 21,
      file: null,
      http: 80,
      https: 443,
      ws: 80,
      wss: 443
    };
    var isWindowsDriveLetter = function(string, normalized2) {
      var second;
      return string.length === 2 && exec(ALPHA, charAt(string, 0)) && ((second = charAt(string, 1)) === ":" || !normalized2 && second === "|");
    };
    var startsWithWindowsDriveLetter = function(string) {
      var third;
      return string.length > 1 && isWindowsDriveLetter(stringSlice(string, 0, 2)) && (string.length === 2 || ((third = charAt(string, 2)) === "/" || third === "\\" || third === "?" || third === "#"));
    };
    var isSingleDot = function(segment) {
      return segment === "." || toLowerCase(segment) === "%2e";
    };
    var isDoubleDot = function(segment) {
      segment = toLowerCase(segment);
      return segment === ".." || segment === "%2e." || segment === ".%2e" || segment === "%2e%2e";
    };
    var SCHEME_START = {};
    var SCHEME = {};
    var NO_SCHEME = {};
    var SPECIAL_RELATIVE_OR_AUTHORITY = {};
    var PATH_OR_AUTHORITY = {};
    var RELATIVE = {};
    var RELATIVE_SLASH = {};
    var SPECIAL_AUTHORITY_SLASHES = {};
    var SPECIAL_AUTHORITY_IGNORE_SLASHES = {};
    var AUTHORITY = {};
    var HOST = {};
    var HOSTNAME = {};
    var PORT = {};
    var FILE = {};
    var FILE_SLASH = {};
    var FILE_HOST = {};
    var PATH_START = {};
    var PATH = {};
    var CANNOT_BE_A_BASE_URL_PATH = {};
    var QUERY = {};
    var FRAGMENT = {};
    var URLState = function(url, isBase, base) {
      var urlString = $toString(url);
      var baseState, failure, searchParams;
      if (isBase) {
        failure = this.parse(urlString);
        if (failure) throw new TypeError2(failure);
        this.searchParams = null;
      } else {
        if (base !== void 0) baseState = new URLState(base, true);
        failure = this.parse(urlString, null, baseState);
        if (failure) throw new TypeError2(failure);
        searchParams = getInternalSearchParamsState(new URLSearchParams2());
        searchParams.bindURL(this);
        this.searchParams = searchParams;
      }
    };
    URLState.prototype = {
      type: "URL",
      // https://url.spec.whatwg.org/#url-parsing
      // eslint-disable-next-line max-statements -- TODO
      parse: function(input, stateOverride, base) {
        var url = this;
        var state = stateOverride || SCHEME_START;
        var pointer = 0;
        var buffer = "";
        var seenAt = false;
        var seenBracket = false;
        var seenPasswordToken = false;
        var codePoints, chr, bufferCodePoints, failure;
        input = $toString(input);
        if (!stateOverride) {
          url.scheme = "";
          url.username = "";
          url.password = "";
          url.host = null;
          url.port = null;
          url.path = [];
          url.query = null;
          url.fragment = null;
          url.cannotBeABaseURL = false;
          input = replace(input, LEADING_C0_CONTROL_OR_SPACE, "");
          input = replace(input, TRAILING_C0_CONTROL_OR_SPACE, "$1");
        }
        input = replace(input, TAB_AND_NEW_LINE, "");
        codePoints = arrayFrom(input);
        while (pointer <= codePoints.length) {
          chr = codePoints[pointer];
          switch (state) {
            case SCHEME_START:
              if (chr && exec(ALPHA, chr)) {
                buffer += toLowerCase(chr);
                state = SCHEME;
              } else if (!stateOverride) {
                state = NO_SCHEME;
                continue;
              } else return INVALID_SCHEME;
              break;
            case SCHEME:
              if (chr && exec(ALPHANUMERIC_PLUS_MINUS_DOT, chr)) {
                buffer += toLowerCase(chr);
              } else if (chr === ":") {
                if (stateOverride && (url.isSpecial() !== hasOwn(specialSchemes, buffer) || buffer === "file" && (url.includesCredentials() || url.port !== null) || url.scheme === "file" && url.host === "")) return;
                url.scheme = buffer;
                if (stateOverride) {
                  if (url.isSpecial() && specialSchemes[url.scheme] === url.port) url.port = null;
                  return;
                }
                buffer = "";
                if (url.scheme === "file") {
                  state = FILE;
                } else if (url.isSpecial() && base && base.scheme === url.scheme) {
                  state = SPECIAL_RELATIVE_OR_AUTHORITY;
                } else if (url.isSpecial()) {
                  state = SPECIAL_AUTHORITY_SLASHES;
                } else if (codePoints[pointer + 1] === "/") {
                  state = PATH_OR_AUTHORITY;
                  pointer++;
                } else {
                  url.cannotBeABaseURL = true;
                  push(url.path, "");
                  state = CANNOT_BE_A_BASE_URL_PATH;
                }
              } else if (!stateOverride) {
                buffer = "";
                state = NO_SCHEME;
                pointer = 0;
                continue;
              } else return INVALID_SCHEME;
              break;
            case NO_SCHEME:
              if (!base || base.cannotBeABaseURL && chr !== "#") return INVALID_SCHEME;
              if (base.cannotBeABaseURL && chr === "#") {
                url.scheme = base.scheme;
                url.path = arraySlice(base.path);
                url.query = base.query;
                url.fragment = "";
                url.cannotBeABaseURL = true;
                state = FRAGMENT;
                break;
              }
              state = base.scheme === "file" ? FILE : RELATIVE;
              continue;
            case SPECIAL_RELATIVE_OR_AUTHORITY:
              if (chr === "/" && codePoints[pointer + 1] === "/") {
                state = SPECIAL_AUTHORITY_IGNORE_SLASHES;
                pointer++;
              } else {
                state = RELATIVE;
                continue;
              }
              break;
            case PATH_OR_AUTHORITY:
              if (chr === "/") {
                state = AUTHORITY;
                break;
              } else {
                state = PATH;
                continue;
              }
            case RELATIVE:
              url.scheme = base.scheme;
              if (chr === EOF) {
                url.username = base.username;
                url.password = base.password;
                url.host = base.host;
                url.port = base.port;
                url.path = arraySlice(base.path);
                url.query = base.query;
              } else if (chr === "/" || chr === "\\" && url.isSpecial()) {
                state = RELATIVE_SLASH;
              } else if (chr === "?") {
                url.username = base.username;
                url.password = base.password;
                url.host = base.host;
                url.port = base.port;
                url.path = arraySlice(base.path);
                url.query = "";
                state = QUERY;
              } else if (chr === "#") {
                url.username = base.username;
                url.password = base.password;
                url.host = base.host;
                url.port = base.port;
                url.path = arraySlice(base.path);
                url.query = base.query;
                url.fragment = "";
                state = FRAGMENT;
              } else {
                url.username = base.username;
                url.password = base.password;
                url.host = base.host;
                url.port = base.port;
                url.path = arraySlice(base.path);
                if (url.path.length) url.path.length--;
                state = PATH;
                continue;
              }
              break;
            case RELATIVE_SLASH:
              if (url.isSpecial() && (chr === "/" || chr === "\\")) {
                state = SPECIAL_AUTHORITY_IGNORE_SLASHES;
              } else if (chr === "/") {
                state = AUTHORITY;
              } else {
                url.username = base.username;
                url.password = base.password;
                url.host = base.host;
                url.port = base.port;
                state = PATH;
                continue;
              }
              break;
            case SPECIAL_AUTHORITY_SLASHES:
              state = SPECIAL_AUTHORITY_IGNORE_SLASHES;
              if (chr !== "/" || codePoints[pointer + 1] !== "/") continue;
              pointer++;
              break;
            case SPECIAL_AUTHORITY_IGNORE_SLASHES:
              if (chr !== "/" && chr !== "\\") {
                state = AUTHORITY;
                continue;
              }
              break;
            case AUTHORITY:
              if (chr === "@") {
                if (seenAt) buffer = "%40" + buffer;
                seenAt = true;
                bufferCodePoints = arrayFrom(buffer);
                for (var i = 0; i < bufferCodePoints.length; i++) {
                  var codePoint = bufferCodePoints[i];
                  if (codePoint === ":" && !seenPasswordToken) {
                    seenPasswordToken = true;
                    continue;
                  }
                  var encodedCodePoints = utf8PercentEncode(codePoint, userinfoPercentEncodeSet);
                  if (seenPasswordToken) url.password += encodedCodePoints;
                  else url.username += encodedCodePoints;
                }
                buffer = "";
              } else if (chr === EOF || chr === "/" || chr === "?" || chr === "#" || chr === "\\" && url.isSpecial()) {
                if (seenAt && buffer === "") return INVALID_AUTHORITY;
                pointer -= arrayFrom(buffer).length + 1;
                buffer = "";
                state = HOST;
              } else buffer += chr;
              break;
            case HOST:
            case HOSTNAME:
              if (stateOverride && url.scheme === "file") {
                state = FILE_HOST;
                continue;
              } else if (chr === ":" && !seenBracket) {
                if (buffer === "") return INVALID_HOST;
                if (stateOverride === HOSTNAME) return;
                failure = url.parseHost(buffer);
                if (failure) return failure;
                buffer = "";
                state = PORT;
              } else if (chr === EOF || chr === "/" || chr === "?" || chr === "#" || chr === "\\" && url.isSpecial()) {
                if (url.isSpecial() && buffer === "") return INVALID_HOST;
                if (stateOverride && buffer === "" && (url.includesCredentials() || url.port !== null)) return;
                failure = url.parseHost(buffer);
                if (failure) return failure;
                buffer = "";
                state = PATH_START;
                if (stateOverride) return;
                continue;
              } else {
                if (chr === "[") seenBracket = true;
                else if (chr === "]") seenBracket = false;
                buffer += chr;
              }
              break;
            case PORT:
              if (exec(DIGIT, chr)) {
                buffer += chr;
              } else if (chr === EOF || chr === "/" || chr === "?" || chr === "#" || chr === "\\" && url.isSpecial() || stateOverride) {
                if (buffer !== "") {
                  var port = parseInt2(buffer, 10);
                  if (port > 65535) return INVALID_PORT;
                  url.port = url.isSpecial() && port === specialSchemes[url.scheme] ? null : port;
                  buffer = "";
                }
                if (stateOverride) return;
                state = PATH_START;
                continue;
              } else return INVALID_PORT;
              break;
            case FILE:
              url.scheme = "file";
              url.host = "";
              if (chr === "/" || chr === "\\") state = FILE_SLASH;
              else if (base && base.scheme === "file") {
                switch (chr) {
                  case EOF:
                    url.host = base.host;
                    url.path = arraySlice(base.path);
                    url.query = base.query;
                    break;
                  case "?":
                    url.host = base.host;
                    url.path = arraySlice(base.path);
                    url.query = "";
                    state = QUERY;
                    break;
                  case "#":
                    url.host = base.host;
                    url.path = arraySlice(base.path);
                    url.query = base.query;
                    url.fragment = "";
                    state = FRAGMENT;
                    break;
                  default:
                    url.host = base.host;
                    if (!startsWithWindowsDriveLetter(join(arraySlice(codePoints, pointer), ""))) {
                      url.path = arraySlice(base.path);
                      url.shortenPath();
                    }
                    state = PATH;
                    continue;
                }
              } else {
                state = PATH;
                continue;
              }
              break;
            case FILE_SLASH:
              if (chr === "/" || chr === "\\") {
                state = FILE_HOST;
                break;
              }
              if (base && base.scheme === "file") {
                url.host = base.host;
                if (!startsWithWindowsDriveLetter(join(arraySlice(codePoints, pointer), "")) && isWindowsDriveLetter(base.path[0], true)) push(url.path, base.path[0]);
              }
              state = PATH;
              continue;
            case FILE_HOST:
              if (chr === EOF || chr === "/" || chr === "\\" || chr === "?" || chr === "#") {
                if (!stateOverride && isWindowsDriveLetter(buffer)) {
                  state = PATH;
                } else if (buffer === "") {
                  url.host = "";
                  if (stateOverride) return;
                  state = PATH_START;
                } else {
                  failure = url.parseHost(buffer);
                  if (failure) return failure;
                  if (url.host === "localhost") url.host = "";
                  if (stateOverride) return;
                  buffer = "";
                  state = PATH_START;
                }
                continue;
              } else buffer += chr;
              break;
            case PATH_START:
              if (url.isSpecial()) {
                state = PATH;
                if (chr !== "/" && chr !== "\\") continue;
              } else if (!stateOverride && chr === "?") {
                url.query = "";
                state = QUERY;
              } else if (!stateOverride && chr === "#") {
                url.fragment = "";
                state = FRAGMENT;
              } else if (chr !== EOF) {
                state = PATH;
                if (chr !== "/") continue;
              }
              break;
            case PATH:
              if (chr === EOF || chr === "/" || chr === "\\" && url.isSpecial() || !stateOverride && (chr === "?" || chr === "#")) {
                if (isDoubleDot(buffer)) {
                  url.shortenPath();
                  if (chr !== "/" && !(chr === "\\" && url.isSpecial())) {
                    push(url.path, "");
                  }
                } else if (isSingleDot(buffer)) {
                  if (chr !== "/" && !(chr === "\\" && url.isSpecial())) {
                    push(url.path, "");
                  }
                } else {
                  if (url.scheme === "file" && !url.path.length && isWindowsDriveLetter(buffer)) {
                    if (url.host !== null && url.host !== "") url.host = "";
                    buffer = charAt(buffer, 0) + ":";
                  }
                  push(url.path, buffer);
                }
                buffer = "";
                if (url.scheme === "file" && (chr === EOF || chr === "?" || chr === "#")) {
                  while (url.path.length > 1 && url.path[0] === "") {
                    shift(url.path);
                  }
                }
                if (chr === "?") {
                  url.query = "";
                  state = QUERY;
                } else if (chr === "#") {
                  url.fragment = "";
                  state = FRAGMENT;
                }
              } else {
                buffer += utf8PercentEncode(chr, pathPercentEncodeSet);
              }
              break;
            case CANNOT_BE_A_BASE_URL_PATH:
              if (chr === "?") {
                url.query = "";
                state = QUERY;
              } else if (chr === "#") {
                url.fragment = "";
                state = FRAGMENT;
              } else if (chr !== EOF) {
                if (chr === " ") {
                  url.path[0] += codePoints[pointer + 1] === "?" || codePoints[pointer + 1] === "#" ? "%20" : " ";
                } else {
                  url.path[0] += utf8PercentEncode(chr, C0ControlPercentEncodeSet);
                }
              }
              break;
            case QUERY:
              if (!stateOverride && chr === "#") {
                url.fragment = "";
                state = FRAGMENT;
              } else if (chr !== EOF) {
                url.query += utf8PercentEncode(chr, url.isSpecial() ? specialQueryPercentEncodeSet : queryPercentEncodeSet);
              }
              break;
            case FRAGMENT:
              if (chr !== EOF) url.fragment += utf8PercentEncode(chr, fragmentPercentEncodeSet);
              break;
          }
          pointer++;
        }
      },
      // https://url.spec.whatwg.org/#host-parsing
      parseHost: function(input) {
        var result, codePoints, index;
        if (charAt(input, 0) === "[") {
          if (charAt(input, input.length - 1) !== "]") return INVALID_HOST;
          result = parseIPv6(stringSlice(input, 1, -1));
          if (!result) return INVALID_HOST;
          this.host = result;
        } else if (!this.isSpecial()) {
          if (exec(FORBIDDEN_HOST_CODE_POINT, input)) return INVALID_HOST;
          result = "";
          codePoints = arrayFrom(input);
          for (index = 0; index < codePoints.length; index++) {
            result += utf8PercentEncode(codePoints[index], C0ControlPercentEncodeSet);
          }
          this.host = result;
        } else {
          input = domainToASCII(percentDecode(input));
          if (input === null || exec(FORBIDDEN_DOMAIN_CODE_POINT, input)) return INVALID_HOST;
          if (endsInNumber(input)) {
            result = parseIPv4(input);
            if (result === null) return INVALID_HOST;
            this.host = result;
          } else {
            this.host = input;
          }
        }
      },
      // https://url.spec.whatwg.org/#cannot-have-a-username-password-port
      cannotHaveUsernamePasswordPort: function() {
        return this.host === null || this.host === "" || this.cannotBeABaseURL || this.scheme === "file";
      },
      // https://url.spec.whatwg.org/#include-credentials
      includesCredentials: function() {
        return this.username !== "" || this.password !== "";
      },
      // https://url.spec.whatwg.org/#is-special
      isSpecial: function() {
        return hasOwn(specialSchemes, this.scheme);
      },
      // https://url.spec.whatwg.org/#shorten-a-urls-path
      shortenPath: function() {
        var path = this.path;
        var pathSize = path.length;
        if (pathSize && (this.scheme !== "file" || pathSize !== 1 || !isWindowsDriveLetter(path[0], true))) {
          path.length--;
        }
      },
      // https://url.spec.whatwg.org/#concept-url-serializer
      serialize: function() {
        var url = this;
        var scheme = url.scheme;
        var username = url.username;
        var password = url.password;
        var host = url.host;
        var port = url.port;
        var path = url.path;
        var query = url.query;
        var fragment2 = url.fragment;
        var output = scheme + ":";
        if (host !== null) {
          output += "//";
          if (url.includesCredentials()) {
            output += username + (password ? ":" + password : "") + "@";
          }
          output += serializeHost(host);
          if (port !== null) output += ":" + port;
        } else if (scheme === "file") output += "//";
        if (host === null && !url.cannotBeABaseURL && path.length > 1 && path[0] === "") output += "/.";
        output += url.cannotBeABaseURL ? path[0] : path.length ? "/" + join(path, "/") : "";
        if (query !== null) output += "?" + query;
        if (fragment2 !== null) output += "#" + fragment2;
        return output;
      },
      // https://url.spec.whatwg.org/#dom-url-href
      setHref: function(href2) {
        var failure = this.parse(href2);
        if (failure) throw new TypeError2(failure);
        this.searchParams.update();
      },
      // https://url.spec.whatwg.org/#dom-url-origin
      getOrigin: function() {
        var scheme = this.scheme;
        var port = this.port;
        if (scheme === "blob") try {
          return new URLConstructor(this.path[0]).origin;
        } catch (error) {
          return "null";
        }
        if (scheme === "file" || !this.isSpecial()) return "null";
        return scheme + "://" + serializeHost(this.host) + (port !== null ? ":" + port : "");
      },
      // https://url.spec.whatwg.org/#dom-url-protocol
      getProtocol: function() {
        return this.scheme + ":";
      },
      setProtocol: function(protocol) {
        this.parse($toString(protocol) + ":", SCHEME_START);
      },
      // https://url.spec.whatwg.org/#dom-url-username
      getUsername: function() {
        return this.username;
      },
      setUsername: function(username) {
        var codePoints = arrayFrom($toString(username));
        if (this.cannotHaveUsernamePasswordPort()) return;
        this.username = "";
        for (var i = 0; i < codePoints.length; i++) {
          this.username += utf8PercentEncode(codePoints[i], userinfoPercentEncodeSet);
        }
      },
      // https://url.spec.whatwg.org/#dom-url-password
      getPassword: function() {
        return this.password;
      },
      setPassword: function(password) {
        var codePoints = arrayFrom($toString(password));
        if (this.cannotHaveUsernamePasswordPort()) return;
        this.password = "";
        for (var i = 0; i < codePoints.length; i++) {
          this.password += utf8PercentEncode(codePoints[i], userinfoPercentEncodeSet);
        }
      },
      // https://url.spec.whatwg.org/#dom-url-host
      getHost: function() {
        var host = this.host;
        var port = this.port;
        return host === null ? "" : port === null ? serializeHost(host) : serializeHost(host) + ":" + port;
      },
      setHost: function(host) {
        if (this.cannotBeABaseURL) return;
        this.parse(host, HOST);
      },
      // https://url.spec.whatwg.org/#dom-url-hostname
      getHostname: function() {
        var host = this.host;
        return host === null ? "" : serializeHost(host);
      },
      setHostname: function(hostname) {
        if (this.cannotBeABaseURL) return;
        this.parse(hostname, HOSTNAME);
      },
      // https://url.spec.whatwg.org/#dom-url-port
      getPort: function() {
        var port = this.port;
        return port === null ? "" : $toString(port);
      },
      setPort: function(port) {
        if (this.cannotHaveUsernamePasswordPort()) return;
        port = $toString(port);
        if (port === "") this.port = null;
        else this.parse(port, PORT);
      },
      // https://url.spec.whatwg.org/#dom-url-pathname
      getPathname: function() {
        var path = this.path;
        return this.cannotBeABaseURL ? path[0] : path.length ? "/" + join(path, "/") : "";
      },
      setPathname: function(pathname) {
        if (this.cannotBeABaseURL) return;
        this.path = [];
        this.parse(pathname, PATH_START);
      },
      // https://url.spec.whatwg.org/#dom-url-search
      getSearch: function() {
        var query = this.query;
        return query ? "?" + query : "";
      },
      setSearch: function(search) {
        search = $toString(search);
        if (search === "") {
          this.query = null;
        } else {
          if (charAt(search, 0) === "?") search = stringSlice(search, 1);
          this.query = "";
          this.parse(search, QUERY);
        }
        this.searchParams.update();
      },
      // https://url.spec.whatwg.org/#dom-url-searchparams
      getSearchParams: function() {
        return this.searchParams.facade;
      },
      // https://url.spec.whatwg.org/#dom-url-hash
      getHash: function() {
        var fragment2 = this.fragment;
        return fragment2 ? "#" + fragment2 : "";
      },
      setHash: function(hash) {
        hash = $toString(hash);
        if (hash === "") {
          this.fragment = null;
          return;
        }
        if (charAt(hash, 0) === "#") hash = stringSlice(hash, 1);
        this.fragment = "";
        this.parse(hash, FRAGMENT);
      },
      update: function() {
        this.query = this.searchParams.serialize() || null;
      }
    };
    var URLConstructor = function URL3(url) {
      var that = anInstance(this, URLPrototype);
      var base = validateArgumentsLength(arguments.length, 1) > 1 ? arguments[1] : void 0;
      var state = setInternalState(that, new URLState(url, false, base));
      if (!DESCRIPTORS) {
        that.href = state.serialize();
        that.origin = state.getOrigin();
        that.protocol = state.getProtocol();
        that.username = state.getUsername();
        that.password = state.getPassword();
        that.host = state.getHost();
        that.hostname = state.getHostname();
        that.port = state.getPort();
        that.pathname = state.getPathname();
        that.search = state.getSearch();
        that.searchParams = state.getSearchParams();
        that.hash = state.getHash();
      }
    };
    var URLPrototype = URLConstructor.prototype;
    var accessorDescriptor = function(getter, setter) {
      return {
        get: function() {
          return getInternalURLState(this)[getter]();
        },
        set: setter && function(value) {
          return getInternalURLState(this)[setter](value);
        },
        configurable: true,
        enumerable: true
      };
    };
    if (DESCRIPTORS) {
      defineBuiltInAccessor(URLPrototype, "href", accessorDescriptor("serialize", "setHref"));
      defineBuiltInAccessor(URLPrototype, "origin", accessorDescriptor("getOrigin"));
      defineBuiltInAccessor(URLPrototype, "protocol", accessorDescriptor("getProtocol", "setProtocol"));
      defineBuiltInAccessor(URLPrototype, "username", accessorDescriptor("getUsername", "setUsername"));
      defineBuiltInAccessor(URLPrototype, "password", accessorDescriptor("getPassword", "setPassword"));
      defineBuiltInAccessor(URLPrototype, "host", accessorDescriptor("getHost", "setHost"));
      defineBuiltInAccessor(URLPrototype, "hostname", accessorDescriptor("getHostname", "setHostname"));
      defineBuiltInAccessor(URLPrototype, "port", accessorDescriptor("getPort", "setPort"));
      defineBuiltInAccessor(URLPrototype, "pathname", accessorDescriptor("getPathname", "setPathname"));
      defineBuiltInAccessor(URLPrototype, "search", accessorDescriptor("getSearch", "setSearch"));
      defineBuiltInAccessor(URLPrototype, "searchParams", accessorDescriptor("getSearchParams"));
      defineBuiltInAccessor(URLPrototype, "hash", accessorDescriptor("getHash", "setHash"));
    }
    defineBuiltIn(URLPrototype, "toJSON", function toJSON() {
      return getInternalURLState(this).serialize();
    }, { enumerable: true });
    defineBuiltIn(URLPrototype, "toString", function toString() {
      return getInternalURLState(this).serialize();
    }, { enumerable: true });
    if (NativeURL) {
      nativeCreateObjectURL = NativeURL.createObjectURL;
      nativeRevokeObjectURL = NativeURL.revokeObjectURL;
      if (nativeCreateObjectURL) defineBuiltIn(URLConstructor, "createObjectURL", bind(nativeCreateObjectURL, NativeURL));
      if (nativeRevokeObjectURL) defineBuiltIn(URLConstructor, "revokeObjectURL", bind(nativeRevokeObjectURL, NativeURL));
    }
    var nativeCreateObjectURL;
    var nativeRevokeObjectURL;
    setToStringTag(URLConstructor, "URL");
    $({ global: true, constructor: true, forced: !USE_NATIVE_URL, sham: !DESCRIPTORS }, {
      URL: URLConstructor
    });
  }
});

// node_modules/core-js-pure/modules/web.url.js
var require_web_url = __commonJS({
  "node_modules/core-js-pure/modules/web.url.js"() {
    "use strict";
    require_web_url_constructor();
  }
});

// node_modules/core-js-pure/modules/web.url.can-parse.js
var require_web_url_can_parse = __commonJS({
  "node_modules/core-js-pure/modules/web.url.can-parse.js"() {
    "use strict";
    var $ = require_export();
    var getBuiltIn = require_get_built_in();
    var fails = require_fails();
    var validateArgumentsLength = require_validate_arguments_length();
    var toString = require_to_string();
    var USE_NATIVE_URL = require_url_constructor_detection();
    var URL3 = getBuiltIn("URL");
    var THROWS_WITHOUT_ARGUMENTS = USE_NATIVE_URL && fails(function() {
      URL3.canParse();
    });
    var WRONG_ARITY = fails(function() {
      return URL3.canParse.length !== 1;
    });
    $({ target: "URL", stat: true, forced: !THROWS_WITHOUT_ARGUMENTS || WRONG_ARITY }, {
      canParse: function canParse(url) {
        var length = validateArgumentsLength(arguments.length, 1);
        var urlString = toString(url);
        var base = length < 2 || arguments[1] === void 0 ? void 0 : toString(arguments[1]);
        try {
          return !!new URL3(urlString, base);
        } catch (error) {
          return false;
        }
      }
    });
  }
});

// node_modules/core-js-pure/modules/web.url.parse.js
var require_web_url_parse = __commonJS({
  "node_modules/core-js-pure/modules/web.url.parse.js"() {
    "use strict";
    var $ = require_export();
    var getBuiltIn = require_get_built_in();
    var validateArgumentsLength = require_validate_arguments_length();
    var toString = require_to_string();
    var USE_NATIVE_URL = require_url_constructor_detection();
    var URL3 = getBuiltIn("URL");
    $({ target: "URL", stat: true, forced: !USE_NATIVE_URL }, {
      parse: function parse(url) {
        var length = validateArgumentsLength(arguments.length, 1);
        var urlString = toString(url);
        var base = length < 2 || arguments[1] === void 0 ? void 0 : toString(arguments[1]);
        try {
          return new URL3(urlString, base);
        } catch (error) {
          return null;
        }
      }
    });
  }
});

// node_modules/core-js-pure/modules/web.url.to-json.js
var require_web_url_to_json = __commonJS({
  "node_modules/core-js-pure/modules/web.url.to-json.js"() {
  }
});

// node_modules/core-js-pure/web/url.js
var require_url = __commonJS({
  "node_modules/core-js-pure/web/url.js"(exports, module) {
    "use strict";
    require_url_search_params();
    require_web_url();
    require_web_url_can_parse();
    require_web_url_parse();
    require_web_url_to_json();
    var path = require_path();
    module.exports = path.URL;
  }
});

// node_modules/core-js-pure/stable/url/index.js
var require_url2 = __commonJS({
  "node_modules/core-js-pure/stable/url/index.js"(exports, module) {
    "use strict";
    var parent2 = require_url();
    module.exports = parent2;
  }
});

// node_modules/core-js-pure/actual/url/index.js
var require_url3 = __commonJS({
  "node_modules/core-js-pure/actual/url/index.js"(exports, module) {
    "use strict";
    var parent2 = require_url2();
    module.exports = parent2;
  }
});

// node_modules/core-js-pure/full/url/index.js
var require_url4 = __commonJS({
  "node_modules/core-js-pure/full/url/index.js"(exports, module) {
    "use strict";
    var parent2 = require_url3();
    module.exports = parent2;
  }
});

// node_modules/core-js-pure/features/url/index.js
var require_url5 = __commonJS({
  "node_modules/core-js-pure/features/url/index.js"(exports, module) {
    "use strict";
    module.exports = require_url4();
  }
});

// adapters/collaboration/content-edit-mutation.js
var import_atob = __toESM(require_atob2(), 1);
var import_btoa = __toESM(require_btoa2(), 1);
import * as Y3 from "yjs";
import { Step as Step2 } from "prosemirror-transform";
import { initProseMirrorDoc, updateYFragment } from "@tiptap/y-tiptap";

// src/editor-model.js
import { Schema } from "prosemirror-model";

// src/editor-schema.js
var canonicalEditorSchema = { "top": "doc", "nodes": [{ "name": "paragraph", "content": "inline*", "group": "block", "attrs": { "relaymarkId": { "default": null } }, "markSet": null }, { "name": "calloutTitle", "content": "text*", "defining": true, "attrs": { "relaymarkId": { "default": null } }, "markSet": null }, { "name": "blockquote", "content": "block+", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null } }, "markSet": [] }, { "name": "bulletList", "content": "listItem+", "group": "block list", "attrs": { "relaymarkId": { "default": null } }, "markSet": [] }, { "name": "doc", "content": "block+", "markSet": [], "attrs": { "relaymark": { "default": {} } } }, { "name": "hardBreak", "group": "inline", "inline": true, "selectable": false, "linebreakReplacement": true, "markSet": [] }, { "name": "horizontalRule", "group": "block", "attrs": { "relaymarkId": { "default": null } }, "markSet": [] }, { "name": "orderedList", "content": "listItem+", "group": "block list", "attrs": { "relaymarkId": { "default": null }, "start": { "default": 1 }, "type": { "default": null } }, "markSet": [] }, { "name": "text", "group": "inline", "markSet": [] }, { "name": "listItem", "content": "paragraph block*", "defining": true, "attrs": { "relaymarkId": { "default": null } }, "markSet": [] }, { "name": "heading", "content": "inline*", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "level": { "default": 1 }, "headingId": { "default": null } }, "markSet": null }, { "name": "taskList", "content": "taskItem+", "group": "block list", "attrs": { "relaymarkId": { "default": null } }, "markSet": [] }, { "name": "taskItem", "content": "paragraph block*", "defining": true, "attrs": { "relaymarkId": { "default": null }, "checked": { "default": false }, "entityId": { "default": null } }, "markSet": [] }, { "name": "table", "tableRole": "table", "content": "tableRow+", "group": "block", "isolating": true, "attrs": { "relaymarkId": { "default": null } }, "markSet": [] }, { "name": "tableRow", "tableRole": "row", "content": "(tableCell | tableHeader)*", "attrs": { "relaymarkId": { "default": null } }, "markSet": [] }, { "name": "tableHeader", "tableRole": "header_cell", "content": "block+", "isolating": true, "attrs": { "relaymarkId": { "default": null }, "colspan": { "default": 1 }, "rowspan": { "default": 1 }, "colwidth": { "default": null }, "align": { "default": null } }, "markSet": [] }, { "name": "tableCell", "tableRole": "cell", "content": "block+", "isolating": true, "attrs": { "relaymarkId": { "default": null }, "colspan": { "default": 1 }, "rowspan": { "default": 1 }, "colwidth": { "default": null }, "align": { "default": null } }, "markSet": [] }, { "name": "codeBlock", "content": "text*", "marks": "", "group": "block", "code": true, "defining": true, "attrs": { "relaymarkId": { "default": null }, "language": { "default": null } }, "markSet": [] }, { "name": "image", "group": "block", "inline": false, "draggable": true, "attrs": { "relaymarkId": { "default": null }, "src": { "default": null }, "alt": { "default": null }, "title": { "default": null }, "width": { "default": null }, "height": { "default": null } }, "markSet": [] }, { "name": "videoEmbed", "group": "block", "atom": true, "draggable": true, "attrs": { "relaymarkId": { "default": null }, "videoId": { "default": null } }, "markSet": [] }, { "name": "relayEntityReference", "group": "block", "atom": true, "selectable": true, "draggable": true, "attrs": { "relaymarkId": { "default": null }, "entityRef": { "default": null }, "entityId": { "default": null }, "entityType": { "default": "Entity" }, "label": { "default": null }, "projection": { "default": "link" }, "source": { "default": null } }, "markSet": [] }, { "name": "relayReference", "group": "inline", "inline": true, "atom": true, "selectable": true, "attrs": { "entityType": { "default": "Entity" }, "entityId": { "default": null }, "label": { "default": null }, "source": { "default": null } }, "markSet": [] }, { "name": "relayTag", "group": "inline", "inline": true, "atom": true, "selectable": true, "attrs": { "id": { "default": null }, "name": { "default": null }, "source": { "default": null } }, "markSet": [] }, { "name": "agentSuggestion", "group": "block", "atom": true, "selectable": false, "attrs": { "relaymarkId": { "default": null }, "review": { "default": "draft" }, "kind": { "default": "note" }, "confidence": { "default": null }, "evidence": { "default": [] }, "content": { "default": "" } }, "markSet": [] }, { "name": "callout", "content": "calloutTitle? block+", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "tone": { "default": "neutral" }, "emphasis": { "default": "soft" } }, "markSet": [] }, { "name": "questionBlock", "content": "questionLabel questionOption*", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "id": { "default": null }, "type": { "default": "short_text" }, "required": { "default": false }, "points": { "default": null }, "min": { "default": null }, "max": { "default": null }, "settings": { "default": {} } }, "markSet": [] }, { "name": "questionLabel", "content": "inline*", "defining": true, "attrs": { "relaymarkId": { "default": null } }, "markSet": null }, { "name": "questionOption", "content": "inline*", "defining": true, "attrs": { "relaymarkId": { "default": null }, "id": { "default": null }, "correct": { "default": false }, "points": { "default": null }, "settings": { "default": {} } }, "markSet": null }, { "name": "relaySourceBundle", "content": "(relayEvidence | relayTranscript | relayNote | relayFile | relayUrl)+", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "id": { "default": null }, "title": { "default": null }, "revision": { "default": null }, "source_hash": { "default": null }, "scope": { "default": "private" }, "confidence": { "default": null } }, "markSet": [] }, { "name": "relayClaim", "content": "paragraph+", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "key": { "default": null }, "subject": { "default": null }, "status": { "default": "unverified" }, "confidence": { "default": null }, "evidence": { "default": null } }, "markSet": [] }, { "name": "relayEvidence", "content": "paragraph*", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "id": { "default": null }, "source": { "default": null }, "source_type": { "default": null }, "source_revision": { "default": null }, "selector": { "default": null }, "label": { "default": null }, "scope": { "default": "private" } }, "markSet": [] }, { "name": "relayComparison", "content": "(paragraph | heading | table)+", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "title": { "default": null }, "subjects": { "default": null }, "criteria": { "default": null }, "values": { "default": null }, "preferred": { "default": null }, "layout": { "default": "table" }, "evidence": { "default": null } }, "markSet": [] }, { "name": "relayTranscript", "content": "paragraph*", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "source": { "default": null }, "speaker": { "default": null }, "speaker_entity": { "default": null }, "start": { "default": null }, "end": { "default": null }, "confidence": { "default": null } }, "markSet": [] }, { "name": "relayAction", "content": "paragraph+", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "proposal_id": { "default": null }, "proposal_record_id": { "default": null }, "proposal_revision": { "default": null }, "action": { "default": null }, "target": { "default": null }, "destination": { "default": null }, "visibility": { "default": "private" }, "review": { "default": "draft" }, "decision_id": { "default": null }, "execution_id": { "default": null }, "undo_id": { "default": null }, "confidence": { "default": null }, "evidence": { "default": null }, "args": { "default": null } }, "markSet": [] }, { "name": "relayPropertySheet", "content": "paragraph*", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "binding": { "default": null }, "fields": { "default": null }, "title": { "default": null }, "presentation": { "default": "stack" } }, "markSet": [] }, { "name": "relayLayout", "content": "(paragraph | heading | relayEntityReference | relayPropertySheet | relayDataView | relayAction)+", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "mode": { "default": "one_column" }, "columns": { "default": null }, "label": { "default": null } }, "markSet": [] }, { "name": "relayFile", "content": "paragraph*", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "id": { "default": null }, "uri": { "default": null }, "label": { "default": null }, "scope": { "default": "private" } }, "markSet": [] }, { "name": "relayNote", "content": "paragraph*", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "document": { "default": null }, "block": { "default": null }, "label": { "default": null }, "scope": { "default": "private" } }, "markSet": [] }, { "name": "relayUrl", "content": "paragraph*", "group": "block", "defining": true, "attrs": { "relaymarkId": { "default": null }, "url": { "default": null }, "label": { "default": null }, "scope": { "default": "private" } }, "markSet": [] }, { "name": "relayButton", "group": "block", "atom": true, "attrs": { "relaymarkId": { "default": null }, "label": { "default": "" }, "kind": { "default": "" }, "target": { "default": "" } }, "markSet": [] }, { "name": "relayAnchor", "group": "block", "atom": true, "attrs": { "relaymarkId": { "default": null }, "name": { "default": "" } }, "markSet": [] }, { "name": "relayConnection", "group": "block", "atom": true, "attrs": { "relaymarkId": { "default": null }, "provider": { "default": "" } }, "markSet": [] }, { "name": "relayDataView", "group": "block", "atom": true, "draggable": true, "attrs": { "relaymarkId": { "default": null }, "source": { "default": null }, "projection": { "default": "chart" }, "filter": { "default": null }, "limit": { "default": null }, "title": { "default": null } }, "markSet": [] }], "marks": [{ "name": "link", "inclusive": true, "attrs": { "href": { "default": null }, "target": { "default": "_blank" }, "rel": { "default": "noopener noreferrer nofollow" }, "class": { "default": null }, "title": { "default": null } }, "excludes": ["link"] }, { "name": "bold", "excludes": ["bold"] }, { "name": "code", "excludes": ["link", "bold", "code", "italic", "strike", "underline", "highlight", "superscript", "subscript"], "code": true }, { "name": "italic", "excludes": ["italic"] }, { "name": "strike", "excludes": ["strike"] }, { "name": "underline", "excludes": ["underline"] }, { "name": "highlight", "excludes": ["highlight"] }, { "name": "superscript", "excludes": ["superscript"] }, { "name": "subscript", "excludes": ["subscript"] }] };

// src/editor-model.js
function createCanonicalEditorSchema() {
  const nodes = Object.fromEntries(canonicalEditorSchema.nodes.map(({ name, markSet, ...spec }) => [
    name,
    { ...spec, ...markSet === null ? {} : { marks: markSet.join(" ") } }
  ]));
  const marks = Object.fromEntries(canonicalEditorSchema.marks.map(({ name, excludes, ...spec }) => [
    name,
    { ...spec, excludes: excludes.join(" ") }
  ]));
  return new Schema({ topNode: canonicalEditorSchema.top, nodes, marks });
}

// src/content-edit.js
import { Step } from "prosemirror-transform";

// src/document-url.js
var import_url = __toESM(require_url5(), 1);

// src/document-links.js
function safeLinkHref(value) {
  if (typeof value !== "string" || !value || /[\s\u0000-\u001f\u007f<>\\]/u.test(value)) return false;
  if (value.startsWith("#")) return value.length > 1;
  if (value.startsWith("/")) return !value.startsWith("//");
  if (/^https?:\/\//iu.test(value)) {
    try {
      const url = new import_url.default(value);
      return !!url.hostname && !url.username && !url.password && ["http:", "https:"].includes(url.protocol);
    } catch {
      return false;
    }
  }
  if (/^relay:(?:entity|note|file|tag)\/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u.test(value)) return true;
  if (/^mailto:/iu.test(value)) return value.slice(7).split("?")[0].length > 0;
  if (/^tel:/iu.test(value)) return /^[+0-9().-]+$/u.test(value.slice(4));
  return false;
}
function safeImageSource(value) {
  if (typeof value !== "string" || value.length > 2048 || !safeLinkHref(value)) return false;
  if (value.startsWith("/")) {
    try {
      return value.split(/[?#]/u)[0].split("/").every((part2) => ![".", ".."].includes(decodeURIComponent(part2)));
    } catch {
      return false;
    }
  }
  if (!/^https:\/\//iu.test(value)) return false;
  try {
    return new import_url.default(value).protocol === "https:";
  } catch {
    return false;
  }
}
var linkDefaults = Object.freeze(Object.fromEntries(Object.entries(canonicalEditorSchema.marks.find((mark) => mark.name === "link").attrs).filter(([name]) => name !== "href").map(([name, spec]) => [name, spec.default])));
function validateLinkAttributes(attributes) {
  if (!attributes || typeof attributes !== "object" || Array.isArray(attributes) || Object.keys(attributes).some((k) => !["href", ...Object.keys(linkDefaults)].includes(k)) || !safeLinkHref(attributes.href)) throw new TypeError("Invalid link href or attributes");
  for (const key2 of Object.keys(linkDefaults)) if (!Object.hasOwn(attributes, key2)) throw new TypeError("Missing link " + key2);
  const { target, rel, class: className, title } = attributes;
  const invalidText = (value) => typeof value !== "string" || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(value);
  if (target !== null && (invalidText(target) || /[\t\r\n]/u.test(target) || target.startsWith("_") && !["_blank", "_self", "_parent", "_top"].includes(target.toLowerCase()))) throw new TypeError("Invalid link target");
  if (rel !== null && invalidText(rel)) throw new TypeError("Invalid link rel");
  if (className !== null && invalidText(className)) throw new TypeError("Invalid link class");
  if (title !== null && invalidText(title)) throw new TypeError("Invalid link title");
  return attributes;
}
function linkProperties(attributes) {
  validateLinkAttributes(attributes);
  return Object.fromEntries(Object.entries(linkDefaults).filter(([key2, value]) => attributes[key2] !== value).map(([key2]) => [key2, attributes[key2]]));
}

// src/directive-registry.js
var directiveSpecifications = [{ "$schema": "../schemas/relaymark-directive.schema.json", "name": "ActionRow", "ast_type": "relay.action_row", "category": "relay_kit", "description": "A reviewable Relay action proposal attached to document context.", "attributes": { "proposal_id": { "type": "string", "description": "Stable generator/client proposal id retained across edits and review decisions; distinct from both the AST block id and the host proposal record id." }, "proposal_record_id": { "type": "string", "description": "Stable host record id used to address authorized review and undo actions; this is an identifier, not an authorization credential." }, "proposal_revision": { "type": "integer", "description": "Positive proposal revision. Editing retains proposal_id and increments this value." }, "action": { "type": "string", "required": true, "description": "Durable Relay.Action.Registry id." }, "target": { "type": "string", "description": "Target entity, event, note, task, or unresolved target reference." }, "destination": { "type": "string", "description": "Optional destination surface or collection for the action." }, "visibility": { "type": "enum", "values": ["private", "org", "unlisted", "public"], "default": "private" }, "review": { "type": "enum", "values": ["draft", "ready", "accepted", "rejected", "undone"], "default": "draft" }, "decision_id": { "type": "string", "description": "Stable id of the durable accept or reject decision. An undone accepted proposal retains its original accept decision id." }, "execution_id": { "type": "string", "description": "Stable host execution id after an accepted proposal mutates durable state." }, "undo_id": { "type": "string", "description": "Stable id of the durable undo operation after an accepted execution is undone." }, "confidence": { "type": "number", "description": "Agent confidence from 0.0 to 1.0 when applicable." }, "evidence": { "type": "array", "items": "string", "description": "Block or source ids that ground the proposal." }, "args": { "type": "object", "description": "Host-validated action arguments." } }, "children": { "mode": "block", "allowed_types": ["paragraph"], "min": 1 }, "validation": ["action must resolve to a host Relay.Action.Registry id before execution", "review must be draft or ready for agent-created blocks", "accepted, rejected, and undone states may only be produced by host review flows", "a lifecycle-aware proposal carries distinct proposal_id and proposal_record_id values, keeps both stable, starts proposal_revision at 1, and increments it on edit", "accepted proposals require decision_id and execution_id", "rejected proposals require decision_id and must not carry execution_id or undo_id", "undone proposals retain the original accept decision_id and execution_id and require a distinct undo_id", "opaque authorization credentials and executable undo tokens must not be embedded in RelayMark", "evidence refs should resolve to known blocks or source manifest entries when present", "visibility must be allowed by the current document and user scope"], "projections": { "relay_kit": "ActionRow", "html": "reviewable-action-card", "plain_text": "action label and review state", "manifest": ["actions"] }, "policy": { "requires_review": true, "requires_evidence": false, "allows_agent_creation": true, "visibility_attribute": "visibility" } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "AgentSuggestion", "ast_type": "relay.agent_suggestion", "category": "relay_kit", "description": "A visible or sidecar suggestion generated by an agent and attached to document context.", "attributes": { "confidence": { "type": "number", "description": "Agent confidence from 0.0 to 1.0 when applicable." }, "evidence": { "type": "array", "items": "string", "description": "Block or source ids that ground the suggestion." }, "review": { "type": "enum", "values": ["draft", "ready", "accepted", "rejected"], "default": "draft" }, "kind": { "type": "enum", "values": ["note", "action", "match", "journey", "source", "share"], "default": "note" }, "anchor": { "type": "string", "description": "Optional block id when source syntax needs an explicit anchor." } }, "children": { "mode": "mixed", "allowed_types": ["paragraph", "text", "relay.entity_ref"], "min": 1 }, "validation": ["agent-created suggestions must remain draft or ready until reviewed", "evidence refs should resolve to known blocks or source manifest entries when present", "anchored sidecar suggestions should compile to annotations instead of visible blocks when the host requests annotation projection"], "projections": { "relay_kit": "AgentSuggestion", "html": "agent-suggestion", "plain_text": "suggestion text", "manifest": [] }, "policy": { "requires_review": true, "requires_evidence": false, "allows_agent_creation": true } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "Callout", "ast_type": "relay.callout", "category": "relay_kit", "description": "A styled document callout with an optional editable title and nested body blocks.", "attributes": { "tone": { "type": "enum", "values": ["neutral", "primary", "secondary", "accent", "info", "success", "warning", "error"], "required": true, "default": "neutral" }, "emphasis": { "type": "enum", "values": ["soft", "strong"], "required": true, "default": "soft" }, "title": { "type": "string", "description": "Plain-source title. The AST stores this as a first child so rich title marks retain identity." } }, "children": { "mode": "block", "min": 1 }, "validation": ["The optional relay.callout_title child is first and unique.", "At least one body block follows the title when present.", "Tone and emphasis use the exact declared values."], "projections": { "html": "section[data-relay-callout]", "plain_text": "title and body text" }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "CalloutTitle", "ast_type": "relay.callout_title", "category": "relay_kit", "description": "An editable callout title with its own stable block identity and inline marks.", "attributes": {}, "children": { "mode": "inline" }, "validation": ["Only a first child of relay.callout, never a standalone block."], "projections": { "html": "p[data-callout-title]", "plain_text": "title text" }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "Claim", "ast_type": "relay.claim", "category": "research", "description": "A factual proposition with explicit evidence and verification state.", "attributes": { "key": { "type": "string", "required": true, "description": "Stable key used to group equivalent or conflicting claims." }, "subject": { "type": "string", "description": "Entity or other host reference that the claim describes." }, "status": { "type": "enum", "values": ["unverified", "supported", "disputed", "refuted", "resolved"], "default": "unverified" }, "confidence": { "type": "number", "description": "Confidence from 0.0 to 1.0 when available." }, "evidence": { "type": "array", "items": "string", "description": "Block or source ids that support or dispute the proposition." } }, "children": { "mode": "block", "allowed_types": ["paragraph"], "min": 1 }, "validation": ["key should be stable across equivalent or conflicting claims", "evidence refs should resolve to known blocks or source manifest entries", "confidence should be between 0.0 and 1.0 when present", "resolved claims should preserve the evidence used for resolution"], "projections": { "relay_kit": "Claim", "html": "research-claim", "plain_text": "claim text and verification state", "manifest": ["claims"] }, "policy": { "requires_review": false, "requires_evidence": true, "allows_agent_creation": true } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "Comparison", "ast_type": "relay.comparison", "category": "research", "description": "A structured, evidence-backed comparison of two or more referenced subjects.", "attributes": { "title": { "type": "string", "description": "Human-readable comparison title." }, "subjects": { "type": "array", "items": "string", "required": true, "description": "Two or more entity or host references being compared." }, "criteria": { "type": "array", "items": "string", "required": true, "description": "Ordered comparison criteria." }, "values": { "type": "object", "required": true, "description": "Criterion-keyed JSON values for each subject." }, "preferred": { "type": "string", "description": "Optional evidence-backed preferred subject reference." }, "layout": { "type": "enum", "values": ["table", "bar", "timeline", "checklist", "radar", "heatmap"], "default": "table" }, "evidence": { "type": "array", "items": "string", "description": "Block or source ids grounding the compared values." } }, "children": { "mode": "block", "allowed_types": ["paragraph", "heading", "table"], "min": 1 }, "validation": ["subjects must contain at least two distinct references", "criteria must contain at least one key", "values should provide a value or an explicit null for every subject and criterion", "preferred should resolve to one of subjects when present", "evidence refs should resolve to known blocks or source manifest entries"], "projections": { "relay_kit": "Comparison", "html": "research-comparison", "plain_text": "comparison title and summary", "manifest": ["comparisons"] }, "policy": { "requires_review": false, "requires_evidence": true, "allows_agent_creation": true } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "DataView", "ast_type": "relay.data_view", "category": "relay_kit", "description": "A bound view over an approved host read model without embedding its records in source.", "capability": "binding.data_view", "fallback": "summary", "attributes": { "source": { "type": "string", "required": true, "description": "Approved host read-model address, not a URL, query, or executable data source." }, "projection": { "type": "enum", "required": true, "values": ["list", "table", "feed", "calendar", "kanban", "chart"] }, "columns": { "type": "array", "items": "string", "description": "Ordered projected field keys." }, "filter": { "type": "object", "description": "Declarative host-allowlisted field keys to JSON scalar or scalar-list values. Nested objects and executable predicates are unsupported; these values are never SQL." }, "sort": { "type": "array", "items": "string", "description": "Ordered host-validated sort keys, optionally prefixed with a minus for descending order." }, "group": { "type": "string", "description": "Optional host field key used for grouping." }, "limit": { "type": "integer", "description": "Requested result limit. Hosts enforce their own stricter bound." }, "title": { "type": "string", "description": "Optional authored view title." } }, "children": { "mode": "mixed", "allowed_types": ["paragraph", "text"], "min": 0 }, "validation": ["source, columns, filters, sort, grouping, and projection must be allowlisted by the host", "source must not contain SQL, a network URL, credentials, or authorization claims", "records remain outside RelayMark and outside collaborative text storage", "rendering is side-effect free"], "projections": { "relay_kit": "DataView", "html": "bound-data-view", "plain_text": "title and host-provided summary", "manifest": [] }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "EntityRef", "ast_type": "relay.entity_reference", "category": "relay_kit", "description": "A renderer-neutral reference to any host-resolved entity.", "capability": "entity.reference", "fallback": "plain_text", "attributes": { "id": { "type": "string", "required": true, "description": "Stable host entity reference. It identifies an entity but grants no access to it." }, "label": { "type": "string", "description": "Optional authored fallback label. Hosts may replace it with an authorized resolved label." }, "projection": { "type": "enum", "values": ["link", "chip", "card"], "default": "link" }, "source": { "type": "string", "description": "Optional exact authored directive source for an offered atom; it must agree with identity, label and projection." } }, "children": { "mode": "mixed", "allowed_types": ["paragraph", "text"], "min": 0 }, "validation": ["id must be resolved and authorized by the host before interactive rendering", "RelayMark carries no entity fields, access claims, or authorization credentials", "an unresolved or unsupported reference renders its authored label or stable inert fallback"], "projections": { "relay_kit": "EntityReference", "html": "entity-reference", "plain_text": "authorized label or authored fallback label", "manifest": ["references"] }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "EvidenceRef", "ast_type": "relay.evidence_ref", "category": "source", "description": "A stable, version-aware reference to evidence from any host-readable source.", "attributes": { "id": { "type": "string", "required": true, "description": "Stable host evidence id used by claims, suggestions, and action proposals; distinct from the AST block id." }, "source": { "type": "string", "required": true, "description": "Host-readable source id or URI." }, "source_type": { "type": "string", "description": "Open source category such as transcript, note, event, file, or URL. The reserved scripture value activates the relaymark.scripture_span profile." }, "source_revision": { "type": "string", "description": "Immutable source revision id, digest, or version token when available." }, "selector": { "type": "object", "description": "Host-interpreted locator such as a time range, text range, field path, or page region. Scripture sources require a lossless relaymark.scripture_span selector." }, "label": { "type": "string", "description": "Human-readable evidence label." }, "scope": { "type": "enum", "values": ["private", "org", "unlisted", "public"], "default": "private" } }, "children": { "mode": "block", "allowed_types": ["paragraph"], "min": 0 }, "validation": ["id must be unique within the document and stable across regenerated revisions", "source must resolve through the host or remain an explicit unresolved review issue", "source_revision should identify immutable evidence when the host can provide one", "selector semantics are defined by source_type and validated by the host", "source_type scripture requires source to resolve to one scripture resource and source_revision to equal its corpus_release_id", "scripture selectors preserve chapter-or-section coordinates and verse_label as a string; ordering is validated against the release coordinate inventory", "scope must be allowed by the current document and user scope"], "projections": { "relay_kit": "EvidenceRef", "html": "evidence-ref", "plain_text": "evidence label or excerpt", "manifest": ["sources"] }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true, "visibility_attribute": "scope" } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "FileRef", "ast_type": "relay.file_ref", "category": "source", "description": "A reference to a file source that grounds nearby content.", "attributes": { "id": { "type": "string", "description": "Host file or media resource id." }, "uri": { "type": "string", "description": "File URI when an id is not yet resolved." }, "label": { "type": "string", "description": "Human-readable source label." }, "scope": { "type": "enum", "values": ["private", "org", "unlisted", "public"], "default": "private" } }, "children": { "mode": "block", "allowed_types": ["paragraph"], "min": 0 }, "validation": ["id or uri should be present", "scope must be allowed by the current document and user scope"], "projections": { "relay_kit": "SourceRef", "html": "source-ref", "plain_text": "file source label", "manifest": ["sources"] }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true, "visibility_attribute": "scope" } }, { "$schema": "../schemas/relaymark-directive.schema.json", "category": "form", "validation": ["Question and option identities are stable; form authorization and publishing remain host-owned."], "projections": { "relay_kit": "FormQuestion", "html": "form-question", "plain_text": "authored labels", "manifest": ["forms"] }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true }, "name": "FormOption", "ast_type": "relay.form_option", "description": "Stable independently editable choice label and authored grading metadata.", "attributes": { "id": { "type": "string", "required": true }, "correct": { "type": "boolean", "default": false }, "points": { "type": "number", "nullable": true }, "settings": { "type": "object", "default": {} } }, "children": { "mode": "inline", "min": 0 } }, { "$schema": "../schemas/relaymark-directive.schema.json", "category": "form", "validation": ["Question and option identities are stable; form authorization and publishing remain host-owned."], "projections": { "relay_kit": "FormQuestion", "html": "form-question", "plain_text": "authored labels", "manifest": ["forms"] }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true }, "name": "FormQuestion", "ast_type": "relay.form_question", "description": "One canonical collaborative form question with rich label and independently identified options.", "attributes": { "id": { "type": "string", "required": true }, "type": { "type": "string", "required": true }, "required": { "type": "boolean", "default": false }, "points": { "type": "number", "nullable": true }, "min": { "type": "number", "nullable": true }, "max": { "type": "number", "nullable": true }, "settings": { "type": "object", "default": {} } }, "children": { "mode": "block", "allowed_types": ["paragraph", "relay.form_option"], "min": 1 } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "Layout", "ast_type": "relay.layout", "category": "relay_kit", "description": "A renderer-neutral grouping hint with a deterministic single-column fallback.", "capability": "layout.adaptive_columns", "fallback": "children", "attributes": { "mode": { "type": "enum", "values": ["one_column", "adaptive_columns"], "default": "one_column" }, "columns": { "type": "integer", "description": "Preferred maximum columns for adaptive layout. Renderers may use fewer." }, "label": { "type": "string", "description": "Optional accessible group label." } }, "children": { "mode": "block", "allowed_types": ["paragraph", "heading", "relay.entity_reference", "relay.property_sheet", "relay.data_view", "relay.action_row"], "min": 1 }, "validation": ["adaptive_columns requires a positive columns value when present", "unsupported layout capability renders children in source order as one column", "layout never changes data semantics, authorization, or action behavior"], "projections": { "relay_kit": "LayoutGroup", "html": "semantic-layout-group", "plain_text": "children in source order", "manifest": [] }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "NoteRef", "ast_type": "relay.note_ref", "category": "source", "description": "A reference to a note or document block that grounds nearby content.", "attributes": { "document": { "type": "string", "description": "Referenced document id." }, "block": { "type": "string", "description": "Referenced block id within the document." }, "label": { "type": "string", "description": "Human-readable source label." }, "scope": { "type": "enum", "values": ["private", "org", "unlisted", "public"], "default": "private" } }, "children": { "mode": "block", "allowed_types": ["paragraph"], "min": 0 }, "validation": ["document or block should resolve to a readable Relay document context", "scope must be allowed by the current document and user scope"], "projections": { "relay_kit": "SourceRef", "html": "source-ref", "plain_text": "note source label", "manifest": ["sources"] }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true, "visibility_attribute": "scope" } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "PaperControl", "ast_type": "relay.paper_control", "category": "relay_kit", "description": "Inert authored Paper button, anchor, or connection.", "capability": "paper.control", "fallback": "plain_text", "attributes": { "control": { "type": "enum", "values": ["button", "anchor", "connection"], "required": true }, "label": { "type": "string" }, "kind": { "type": "enum", "values": ["anchor", "link", "command"] }, "target": { "type": "string" }, "name": { "type": "string" }, "provider": { "type": "string" }, "source": { "type": "string", "required": true } }, "children": { "mode": "none" }, "validation": ["Exactly the fields for the discriminant and canonical authored source are present", "Navigation, command execution, authorization and connection hydration belong to the host"], "projections": { "plain_text": "authored label or name", "manifest": [] }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": false } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "PropertySheet", "ast_type": "relay.property_sheet", "category": "relay_kit", "description": "A schema-bound property group whose values and edit policy are supplied by the host.", "capability": "binding.property_sheet", "fallback": "summary", "attributes": { "binding": { "type": "string", "required": true, "description": "Approved host binding address. This is a schema/read-model address, never a resolved value." }, "fields": { "type": "array", "items": "string", "required": true, "description": "Ordered host field keys to request from the binding." }, "title": { "type": "string", "description": "Optional authored group title." }, "presentation": { "type": "enum", "values": ["stack", "inline", "compact"], "default": "stack" } }, "children": { "mode": "block", "allowed_types": ["paragraph"], "min": 0 }, "validation": ["binding must be allowlisted and resolved by the host", "fields must contain only keys exposed by the host schema projection", "values, editability, visibility, validation, and mutation action ids never appear in RelayMark source", "removing this block changes composition only and cannot delete bound domain data"], "projections": { "relay_kit": "PropertySheet", "html": "property-sheet", "plain_text": "title and field labels supplied by the host", "manifest": [] }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "SourceBundle", "ast_type": "relay.source_bundle", "category": "source", "description": "A bundle of source references that grounds a note, summary, action, or suggestion.", "attributes": { "id": { "type": "string", "required": true, "description": "Stable host source-bundle id for evidence references; distinct from the AST block id." }, "title": { "type": "string", "description": "Human-readable source bundle title." }, "revision": { "type": "integer", "description": "Non-negative bundle revision. Increment when the bundle membership or locators change." }, "source_hash": { "type": "string", "description": "Host-computed digest of the exact source revision set when available." }, "scope": { "type": "enum", "values": ["private", "org", "unlisted", "public"], "default": "private" }, "confidence": { "type": "number", "description": "Grounding confidence from 0.0 to 1.0 when applicable." } }, "children": { "mode": "block", "allowed_types": ["relay.evidence_ref", "relay.transcript_segment", "relay.note_ref", "relay.file_ref", "relay.url_ref"], "min": 1 }, "validation": ["id must be unique within the document", "revision must be a non-negative integer when present", "the same id and revision must identify the same bundle membership and locators", "children must resolve to concrete source refs or draft source resolution issues", "scope must be allowed by the current document and user scope"], "projections": { "relay_kit": "SourceBundle", "html": "source-bundle", "plain_text": "source labels", "manifest": ["sources"] }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true, "visibility_attribute": "scope" } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "TranscriptRange", "ast_type": "relay.transcript_segment", "category": "transcript", "description": "A range or segment from a transcript source.", "attributes": { "source": { "type": "string", "description": "Transcript resource id or URI." }, "speaker": { "type": "string", "description": "Speaker label when known." }, "speaker_entity": { "type": "string", "description": "Speaker entity reference when resolved." }, "start": { "type": "string", "required": true, "description": "Start timestamp in HH:MM:SS, MM:SS, or milliseconds string form." }, "end": { "type": "string", "required": true, "description": "End timestamp in HH:MM:SS, MM:SS, or milliseconds string form." }, "confidence": { "type": "number", "description": "Transcript confidence from 0.0 to 1.0 when applicable." } }, "children": { "mode": "block", "allowed_types": ["paragraph"], "min": 0 }, "validation": ["start must be less than or equal to end when both timestamps can be parsed", "source should resolve to a transcript resource when present", "speaker_entity should resolve to an entity ref when present"], "projections": { "relay_kit": "TranscriptSegment", "html": "transcript-segment", "plain_text": "timestamp and transcript text", "manifest": ["sources"] }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "UrlRef", "ast_type": "relay.url_ref", "category": "source", "description": "A reference to a URL source that grounds nearby content.", "attributes": { "url": { "type": "string", "required": true, "description": "Source URL." }, "label": { "type": "string", "description": "Human-readable source label." }, "scope": { "type": "enum", "values": ["private", "org", "unlisted", "public"], "default": "private" } }, "children": { "mode": "block", "allowed_types": ["paragraph"], "min": 0 }, "validation": ["url must use an allowed URL scheme", "scope must be allowed by the current document and user scope"], "projections": { "relay_kit": "SourceRef", "html": "source-ref", "plain_text": "url source label", "manifest": ["sources"] }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": true, "visibility_attribute": "scope" } }, { "$schema": "../schemas/relaymark-directive.schema.json", "name": "VideoEmbed", "ast_type": "relay.video_embed", "category": "relay_kit", "description": "An authored video reference whose playback details are resolved by the host.", "attributes": { "videoId": { "type": "string", "required": true, "description": "Canonical lowercase video UUID; identifies media but grants no access." } }, "children": { "mode": "none" }, "validation": ["videoId is a canonical lowercase UUID", "Playback metadata and upload state are not authored source", "The host authorizes and resolves media before playback"], "projections": { "plain_text": "video reference" }, "policy": { "requires_review": false, "requires_evidence": false, "allows_agent_creation": false } }];

// src/registry.js
var byName = new Map(directiveSpecifications.map((value) => [value.name, value]));
var byType = new Map(directiveSpecifications.map((value) => [value.ast_type, value]));
function directiveForType(type) {
  return byType.get(type);
}

// src/document-directives.js
var definitions = [
  ["relay.source_bundle", "relaySourceBundle"],
  ["relay.claim", "relayClaim"],
  ["relay.evidence_ref", "relayEvidence"],
  ["relay.comparison", "relayComparison"],
  ["relay.transcript_segment", "relayTranscript"],
  ["relay.action_row", "relayAction"],
  ["relay.property_sheet", "relayPropertySheet"],
  ["relay.layout", "relayLayout"],
  ["relay.file_ref", "relayFile"],
  ["relay.note_ref", "relayNote"],
  ["relay.url_ref", "relayUrl"]
];
var blockNames = { paragraph: ["paragraph"], heading: ["heading"], quote: ["blockquote"], list: ["bulletList", "orderedList"], list_item: ["listItem"], task_list: ["taskList"], task_item: ["taskItem"], code: ["codeBlock"], horizontal_rule: ["horizontalRule"], image: ["image"], table: ["table"], table_row: ["tableRow"], table_cell: ["tableCell", "tableHeader"], "relay.callout": ["callout"], "relay.callout_title": ["calloutTitle"], "relay.video_embed": ["videoEmbed"], "relay.entity_reference": ["relayEntityReference"], "relay.agent_suggestion": ["agentSuggestion"], "relay.data_view": ["relayDataView"], "relay.form_question": ["questionBlock"], "relay.form_option": ["questionOption"], "relay.paper_control": ["relayButton", "relayAnchor", "relayConnection"], ...Object.fromEntries(definitions.map(([type, name]) => [type, [name]])) };
var canonicalDirectiveNodes = Object.freeze(definitions.map(([type, name]) => {
  const spec = directiveForType(type), allowed_children = spec.children.allowed_types, pm_allowed_children = allowed_children.flatMap((t) => {
    const names2 = blockNames[t];
    if (!names2) throw new TypeError("Unsupported directive child specification " + t);
    return names2;
  });
  const expression = pm_allowed_children.length === 1 ? pm_allowed_children[0] : "(" + pm_allowed_children.join(" | ") + ")";
  return Object.freeze({ type, name, content: expression + (spec.children.min > 0 ? "+" : "*"), attributes: spec.attributes, allowed_children, pm_allowed_children, minimum_children: spec.children.min || 0 });
}));
function directiveNodeForName(name) {
  return canonicalDirectiveNodes.find((n) => n.name === name);
}
function authoredDirectiveProps(shape, attrs) {
  if (!attrs || typeof attrs !== "object" || Array.isArray(attrs)) throw new TypeError("Invalid directive attrs");
  for (const key2 of Object.keys(attrs)) if (key2 !== "relaymarkId" && !Object.hasOwn(shape.attributes, key2)) throw new TypeError("Unsupported authored directive field " + key2);
  const props = {};
  for (const [key2, spec] of Object.entries(shape.attributes)) {
    let value = attrs[key2];
    if (value == null) {
      if (Object.hasOwn(spec, "default")) value = spec.default;
      else if (spec.required) throw new TypeError("Missing authored directive " + key2);
      else continue;
    }
    const okay = ["string", "enum"].includes(spec.type) ? typeof value === "string" : spec.type === "boolean" ? typeof value === "boolean" : spec.type === "integer" ? Number.isSafeInteger(value) : spec.type === "number" ? typeof value === "number" && Number.isFinite(value) : spec.type === "array" ? Array.isArray(value) : spec.type === "object" ? value && typeof value === "object" && !Array.isArray(value) : false;
    if (!okay || spec.type === "enum" && !spec.values.includes(value) || spec.items === "string" && value.some((v) => typeof v !== "string")) throw new TypeError("Invalid authored directive " + key2);
    jsonValue(value);
    props[key2] = value;
  }
  return props;
}
function jsonValue(value, depth = 0) {
  if (depth > 64) throw new TypeError("Directive JSON nesting");
  if (value === null || typeof value === "boolean" || typeof value === "string") return;
  if (typeof value === "number" && Number.isFinite(value)) return;
  if (Array.isArray(value)) {
    for (const child of value) jsonValue(child, depth + 1);
    return;
  }
  if (value && Object.getPrototypeOf(value) === Object.prototype) {
    for (const child of Object.values(value)) jsonValue(child, depth + 1);
    return;
  }
  throw new TypeError("Invalid directive JSON value");
}

// src/document-atoms.js
var uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
var entityType = /^[A-Z][A-Za-z0-9]*(?: [A-Z][A-Za-z0-9]*)*$/u;
var tagName = /^[a-z0-9][a-z0-9_-]*$/u;
function object(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new TypeError(`Invalid ${label}`);
  return value;
}
function only(value, allowed, label) {
  for (const key2 of Object.keys(object(value, label))) {
    if (!allowed.includes(key2)) throw new TypeError(`Unsupported ${label} field: ${key2}`);
  }
}
function identity(id2) {
  if (typeof id2 !== "string" || !uuid.test(id2)) throw new TypeError("Invalid canonical atom UUID");
  return id2;
}
function buildEntityReferenceSource({ entityType: type, entityId: id2, label }) {
  if (typeof type !== "string" || !entityType.test(type) || type === "Tag" || typeof label !== "string" || !label) {
    throw new TypeError("Invalid authored reference label or type");
  }
  const quoted = label !== label.trim() || /[\r\n\[\]"\\`*_<>!]/u.test(label);
  const encoded = quoted ? '"' + label.split("").map((c) => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0")).join("") + '"' : label;
  return `[[${type}: ${identity(id2)} | ${encoded}]]`;
}
function referenceSource(type, id2, label) {
  return buildEntityReferenceSource({ entityType: type, entityId: id2, label });
}
function tagSource(id2, name) {
  if (typeof name !== "string" || !tagName.test(name)) throw new TypeError("Invalid authored tag name");
  return `[[Tag: ${identity(id2)} | #${name}]]`;
}
function mapAtom(node) {
  only(node, ["type", "attrs"], "atom");
  if (node.type === "relayReference") {
    only(node.attrs, ["entityType", "entityId", "label", "source", "status", "subtitle"], "reference attrs");
    const { entityType: type, entityId: id2, label, source, status, subtitle } = node.attrs;
    if (status != null || subtitle != null || source !== referenceSource(type, id2, label)) {
      throw new TypeError("Unsupported reference hydration or source");
    }
    return { type: "relay.entity_ref", id: id2, label, props: { entityType: type, source } };
  }
  if (node.type === "relayTag") {
    only(node.attrs, ["id", "name", "color", "source"], "tag attrs");
    const { id: id2, name, color, source } = node.attrs;
    if (color != null || source !== tagSource(id2, name)) throw new TypeError("Unsupported tag color or source");
    return { type: "relay.tag_ref", id: id2, label: `#${name}`, props: { name, source } };
  }
  throw new TypeError(`Unsupported inline atom ${String(node.type)}`);
}

// src/document-inline.js
var textMarkNames = ["link", "bold", "code", "italic", "strike", "underline", "highlight", "superscript", "subscript"];
var markTypes = textMarkNames;
var inlineTypes = {
  link: "link",
  bold: "strong",
  code: "code_span",
  italic: "emphasis",
  strike: "strikethrough",
  underline: "underline",
  highlight: "highlight",
  superscript: "superscript",
  subscript: "subscript"
};
var pmTypes = Object.fromEntries(Object.entries(inlineTypes).map(([pm, ast]) => [ast, pm]));
function object2(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new TypeError(`Invalid ${label}`);
  return value;
}
function keys(value, allowed, label) {
  for (const key2 of Object.keys(object2(value, label))) {
    if (!allowed.includes(key2)) throw new TypeError(`Unsupported ${label} field: ${key2}`);
  }
}
function href(value) {
  if (!safeLinkHref(value)) {
    throw new TypeError("Invalid link href");
  }
  return value;
}
function mapInline(node) {
  object2(node, "inline");
  if (node.type === "relayReference" || node.type === "relayTag") return mapAtom(node);
  if (node.type === "hardBreak") {
    keys(node, ["type"], "hardBreak");
    return { type: "hard_break" };
  }
  keys(node, ["type", "text", "marks"], "text");
  if (node.type !== "text" || typeof node.text !== "string" || !node.text) {
    throw new TypeError("Expected nonempty text");
  }
  let result = { type: "text", text: node.text };
  const marks = node.marks ?? [];
  if (!Array.isArray(marks)) throw new TypeError("Invalid text marks");
  let previous = -1;
  for (const mark of marks) {
    keys(mark, ["type", "attrs"], "mark");
    const rank = markTypes.indexOf(mark.type);
    if (rank < 0 || rank <= previous || mark.type === "code" && marks.length !== 1) {
      throw new TypeError("Unsupported or noncanonical text marks");
    }
    previous = rank;
    if (mark.type === "link") {
      validateLinkAttributes(mark.attrs);
    } else if (mark.attrs !== void 0) {
      throw new TypeError(`Unsupported ${mark.type} attrs`);
    }
  }
  for (const mark of marks.toReversed()) {
    result = {
      type: inlineTypes[mark.type],
      ...mark.type === "link" ? { href: href(mark.attrs.href), ...Object.keys(linkProperties(mark.attrs)).length ? { props: linkProperties(mark.attrs) } : {} } : {},
      content: [result]
    };
  }
  return result;
}

// src/document-reference.js
var uuid2 = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;
var projections = /* @__PURE__ */ new Set(["link", "chip", "card"]);
function parseEntityReferenceSource(source) {
  if (typeof source !== "string" || source.length > 16384) return null;
  const match = source.match(/^@EntityRef\s*\(([\s\S]*?)\)\s*\{(?:\r\n|\n|\r)  ([^\r\n{}]+)(?:\r\n|\n|\r)\}$/u);
  if (!match) return null;
  const attrs = {};
  let rest = match[1].trim();
  while (rest) {
    const key2 = rest.match(/^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*/u);
    if (!key2 || !["id", "label", "projection"].includes(key2[1]) || Object.hasOwn(attrs, key2[1])) return null;
    rest = rest.slice(key2[0].length);
    const value = rest.match(/^"(?:\\.|[^"\\])*"/u);
    if (!value) return null;
    try {
      attrs[key2[1]] = JSON.parse(value[0]);
    } catch {
      return null;
    }
    if (typeof attrs[key2[1]] !== "string") return null;
    rest = rest.slice(value[0].length).trimStart();
    if (!rest) break;
    if (!rest.startsWith(",")) return null;
    rest = rest.slice(1).trimStart();
    if (!rest) return null;
  }
  if (typeof attrs.id !== "string" || !attrs.id.startsWith("entity:")) return null;
  const entityId2 = attrs.id.slice("entity:".length);
  if (!uuid2.test(entityId2)) return null;
  const projection = attrs.projection || "link";
  if (!projections.has(projection)) return null;
  const body = match[2];
  if (body !== body.trim() || /\[\[|\]\]|\]\(relay:|^[@#]/u.test(body)) return null;
  const label = attrs.label || body;
  if (!label || label !== label.trim() || /[\r\n]/u.test(label)) return null;
  return { id: attrs.id, entityId: entityId2, label, projection, body, source };
}

// src/document-controls.js
var fields = { button: ["label", "kind", "target"], anchor: ["name"], connection: ["provider"] };
var names = { button: "Button", anchor: "Anchor", connection: "Connection" };
var nodeNames = { button: "relayButton", anchor: "relayAnchor", connection: "relayConnection" };
var anchorName = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}(?![\s\S])/u;
var providerName = /^[a-z][a-z0-9_-]*(?![\s\S])/u;
var command = /^\/[a-z][a-z0-9._-]*(?: [^\u0000-\u001f\u007f]+)?(?![\s\S])/u;
var safeLink = (value) => !/[\s\u0000-\u001f\u007f\\]/u.test(value) && (/^\/(?!\/)/u.test(value) || /^https?:\/\/[^/?#]+/iu.test(value) || /^mailto:[^?]+/iu.test(value));
function object3(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new TypeError("Invalid paper control");
}
function canonicalPaperControlSource(control, authored) {
  object3(authored);
  const allowed = fields[control];
  if (!allowed || Object.keys(authored).length !== allowed.length || Object.keys(authored).some((key2) => !allowed.includes(key2)) || allowed.some((key2) => typeof authored[key2] !== "string")) throw new TypeError("Invalid paper control fields");
  if (control === "button" && (!authored.label.trim() || !["anchor", "link", "command"].includes(authored.kind) || !(authored.kind === "anchor" ? anchorName.test(authored.target) : authored.kind === "link" ? safeLink(authored.target) : command.test(authored.target)))) {
    throw new TypeError("Invalid paper button");
  }
  if (control === "anchor" && !anchorName.test(authored.name)) throw new TypeError("Invalid paper anchor");
  if (control === "connection" && !providerName.test(authored.provider)) throw new TypeError("Invalid paper connection");
  const source = `@${names[control]}(${allowed.map((key2) => `${key2}: ${JSON.stringify(authored[key2])}`).join(", ")})`;
  if (source.length > 16384) throw new TypeError("Paper control source exceeds the draft limit");
  return source;
}
function paperControlKind(nodeName) {
  return Object.keys(nodeNames).find((key2) => nodeNames[key2] === nodeName);
}

// src/document-suggestion.js
var reviews = /* @__PURE__ */ new Set(["draft", "ready"]);
var kinds = /* @__PURE__ */ new Set(["note", "action", "match", "journey", "source", "share"]);
function assertAgentSuggestion(review, kind, confidence, evidence, content2) {
  if (!reviews.has(review) || !kinds.has(kind) || !(confidence === null || typeof confidence === "number" && Number.isFinite(confidence) && confidence >= 0 && confidence <= 1) || !Array.isArray(evidence) || evidence.length > 64 || evidence.some((id2) => typeof id2 !== "string" || id2.length === 0 || id2.length > 128 || /[\u0000-\u001f\u007f]/u.test(id2)) || new Set(evidence).size !== evidence.length || typeof content2 !== "string" || content2.length === 0 || content2.length > 32768 || content2 !== content2.trim() || content2.includes("\r") || content2.includes("\0")) {
    throw new TypeError("Invalid authored AgentSuggestion");
  }
  return { review, kind, confidence, evidence, content: content2 };
}

// src/document-adapter.js
var identifiedDocumentNodeNames = Object.freeze(["paragraph", "calloutTitle", "blockquote", "bulletList", "horizontalRule", "orderedList", "listItem", "heading", "taskList", "taskItem", "table", "tableRow", "tableHeader", "tableCell", "codeBlock", "image", "videoEmbed", "relayEntityReference", "agentSuggestion", "callout", "questionBlock", "questionLabel", "questionOption", "relayButton", "relayAnchor", "relayConnection", "relayDataView"].concat(canonicalDirectiveNodes.map((shape) => shape.name)));
var blockId = /^b[0-9a-f]{12}4[0-9a-f]{3}[89ab][0-9a-f]{15}$/u;
var alignments = /* @__PURE__ */ new Set([null, "left", "center", "right"]);
var maxRows = 256;
var maxColumns = 256;
var maxCells = 4096;
var headingId = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/u;
var entityId = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;
var maxTaskDepth = 16;
var maxListDepth = 16;
var maxDocumentDepth = 64;
var maxTaskChildren = 4096;
function proseMirrorToRelayMark(prosemirror) {
  assertObject(prosemirror, "doc");
  onlyKeys(prosemirror, ["type", "content", "attrs"], "doc");
  const metadata = prosemirror.attrs && Object.hasOwn(prosemirror.attrs, "relaymark") ? prosemirror.attrs.relaymark : {};
  if (prosemirror.attrs !== void 0) {
    assertObject(prosemirror.attrs, "doc attributes");
    onlyKeys(prosemirror.attrs, ["relaymark"], "doc attributes");
  }
  assertAuthoredMetadata(metadata);
  requireType(prosemirror, "doc");
  assertContentDepth(prosemirror);
  const seen = /* @__PURE__ */ new Set();
  const blocks = children(prosemirror, "doc", 1).map((node) => mapBlock(node, seen, 0));
  return { type: "relaymark.document", blocks, ...metadata };
}
function mapBlock(node, seen, calloutDepth) {
  const shape = directiveNodeForName(node?.type);
  if (shape) {
    checkNode(node, shape.name, seen, Object.keys(shape.attributes));
    const props = authoredDirectiveProps(shape, node.attrs);
    const content2 = children(node, shape.name, shape.minimum_children).map((child) => mapBlock(child, seen, calloutDepth));
    if (content2.some((child) => !shape.allowed_children.includes(child.type))) throw new TypeError("Unsupported authored directive child");
    return { id: node.attrs.relaymarkId, type: shape.type, props, content: content2 };
  }
  switch (node?.type) {
    case "paragraph":
      return mapParagraph(node, seen);
    case "questionBlock":
      return mapQuestion(node, seen);
    case "relayDataView":
      return mapDataView(node, seen);
    case "heading":
      return mapHeading(node, seen);
    case "blockquote":
      return mapQuote(node, seen, calloutDepth);
    case "bulletList":
      return mapList(node, seen, false, 0);
    case "orderedList":
      return mapList(node, seen, true, 0);
    case "taskList":
      return mapTaskList(node, seen, 0);
    case "codeBlock":
      return mapCode(node, seen);
    case "horizontalRule":
      return mapRule(node, seen);
    case "image":
      return mapImage(node, seen);
    case "videoEmbed":
      return mapVideo(node, seen);
    case "relayEntityReference":
      return mapEntityReference(node, seen);
    case "relayButton":
    case "relayAnchor":
    case "relayConnection":
      return mapPaperControl(node, seen);
    case "agentSuggestion":
      return mapAgentSuggestion(node, seen);
    case "callout":
      return mapCallout(node, seen, calloutDepth);
    case "table": {
      const table = mapTable(node, seen);
      validateGrid(table);
      return table;
    }
    default:
      throw new TypeError(`Unsupported canonical block: ${String(node?.type)}`);
  }
}
var calloutTones = /* @__PURE__ */ new Set(["neutral", "primary", "secondary", "accent", "info", "success", "warning", "error"]);
var calloutEmphases = /* @__PURE__ */ new Set(["soft", "strong"]);
function checkCalloutProps(tone, emphasis) {
  if (!calloutTones.has(tone) || !calloutEmphases.has(emphasis)) {
    throw new TypeError("Unsupported callout tone or emphasis");
  }
}
function mapCallout(node, seen, depth) {
  if (depth >= 8) throw new TypeError("Callout nesting exceeds the draft limit");
  checkNode(node, "callout", seen, ["tone", "emphasis"]);
  const { tone, emphasis } = node.attrs;
  checkCalloutProps(tone, emphasis);
  const items = children(node, "callout", 1);
  if (items[0]?.type === "calloutTitle" && items.length < 2) {
    throw new TypeError("Callout requires a body block");
  }
  return {
    id: node.attrs.relaymarkId,
    type: "relay.callout",
    props: { tone, emphasis },
    content: items.map((item, index) => index === 0 && item.type === "calloutTitle" ? mapCalloutTitle(item, seen) : mapBlock(item, seen, depth + 1))
  };
}
function mapCalloutTitle(node, seen) {
  checkNode(node, "calloutTitle", seen);
  const items = inlineChildren(node, "calloutTitle");
  if (items.some((item) => item.type !== "text")) throw new TypeError("Unsupported callout title inline node");
  return {
    id: node.attrs.relaymarkId,
    type: "relay.callout_title",
    content: items.map(mapInline)
  };
}
function mapHeading(node, seen) {
  checkNode(node, "heading", seen, ["level", "headingId"]);
  const { level, headingId: anchor } = node.attrs;
  checkHeading(level, anchor);
  return {
    id: node.attrs.relaymarkId,
    type: "heading",
    props: { level, headingId: anchor },
    content: inlineChildren(node, "heading").map(mapInline)
  };
}
function checkHeading(level, anchor) {
  if (!Number.isInteger(level) || level < 1 || level > 6 || anchor !== null && (typeof anchor !== "string" || !headingId.test(anchor))) {
    throw new TypeError("Invalid heading level or headingId");
  }
}
function mapQuote(node, seen, calloutDepth) {
  checkNode(node, "blockquote", seen);
  return { id: node.attrs.relaymarkId, type: "quote", content: children(node, "blockquote", 1).map((child) => mapBlock(child, seen, calloutDepth)) };
}
function mapList(node, seen, ordered, depth) {
  if (depth >= maxListDepth) throw new TypeError("Unsupported nested list depth");
  checkNode(node, ordered ? "orderedList" : "bulletList", seen, ordered ? ["start", "type"] : []);
  if (ordered && node.attrs.type !== null) throw new TypeError("Unsupported ordered-list type");
  const props = ordered ? { kind: "ordered", start: node.attrs.start } : { kind: "bullet" };
  if (ordered) checkListStart(props.start);
  return {
    id: node.attrs.relaymarkId,
    type: "list",
    props,
    content: children(node, node.type, 1).map((child) => mapListItem(child, seen, depth))
  };
}
function checkListStart(start) {
  if (!Number.isSafeInteger(start) || start < 1) throw new TypeError("Invalid ordered-list start");
}
function mapListItem(node, seen, depth) {
  checkNode(node, "listItem", seen);
  const items = children(node, "listItem", 1);
  if (items[0]?.type !== "paragraph") throw new TypeError("List item must start with a paragraph");
  return {
    id: node.attrs.relaymarkId,
    type: "list_item",
    content: [mapParagraph(items[0], seen), ...items.slice(1).map((item) => ["bulletList", "orderedList"].includes(item.type) ? mapList(item, seen, item.type === "orderedList", depth + 1) : mapBlock(item, seen, 0))]
  };
}
function assertContentDepth(node, depth = 0) {
  if (depth > maxDocumentDepth) throw new TypeError(" document nesting limit exceeded");
  if (Array.isArray(node?.content)) {
    for (const child of node.content) assertContentDepth(child, depth + 1);
  }
}
function checkTaskProps(checked, linkedEntityId) {
  if (typeof checked !== "boolean" || linkedEntityId !== null && (typeof linkedEntityId !== "string" || !entityId.test(linkedEntityId))) {
    throw new TypeError("Invalid task checked state or entityId");
  }
}
function taskChildren(items, label) {
  if (items[0]?.type !== "paragraph") {
    throw new TypeError(`Unsupported ${label} children`);
  }
}
function mapTaskList(node, seen, depth) {
  if (depth >= maxTaskDepth) throw new TypeError("Task list nesting exceeds the draft limit");
  checkNode(node, "taskList", seen);
  const items = children(node, "taskList", 1);
  if (items.length > maxTaskChildren) throw new TypeError("Task list exceeds the draft child limit");
  return {
    id: node.attrs.relaymarkId,
    type: "task_list",
    content: items.map((item) => mapTaskItem(item, seen, depth))
  };
}
function mapTaskItem(node, seen, depth) {
  checkNode(node, "taskItem", seen, ["checked", "entityId"]);
  if (!Object.hasOwn(node.attrs, "checked") || !Object.hasOwn(node.attrs, "entityId")) {
    throw new TypeError("Task item requires normalized checked and entityId attributes");
  }
  checkTaskProps(node.attrs.checked, node.attrs.entityId);
  const items = children(node, "taskItem", 1);
  if (items.length > maxTaskChildren) throw new TypeError("Task item exceeds the draft child limit");
  taskChildren(items, "task item");
  return {
    id: node.attrs.relaymarkId,
    type: "task_item",
    props: { checked: node.attrs.checked, entityId: node.attrs.entityId },
    content: items.map((item) => item.type === "taskList" ? mapTaskList(item, seen, depth + 1) : mapBlock(item, seen, 0))
  };
}
function mapCode(node, seen) {
  checkNode(node, "codeBlock", seen, ["language"]);
  checkLanguage(node.attrs.language);
  return {
    id: node.attrs.relaymarkId,
    type: "code",
    props: { language: node.attrs.language },
    content: inlineChildren(node, "codeBlock").map(mapText)
  };
}
function checkLanguage(language) {
  if (language !== null && (typeof language !== "string" || /[\r\n]/u.test(language))) {
    throw new TypeError("Invalid code language");
  }
}
function mapRule(node, seen) {
  checkNode(node, "horizontalRule", seen);
  if (node.content !== void 0 && children(node, "horizontalRule").length !== 0) {
    throw new TypeError("Horizontal rule cannot have children");
  }
  return { id: node.attrs.relaymarkId, type: "horizontal_rule", content: [] };
}
function mapImage(node, seen) {
  checkNode(node, "image", seen, ["src", "alt", "title", "width", "height"]);
  if (node.content !== void 0 && children(node, "image").length !== 0) {
    throw new TypeError("Image cannot have children");
  }
  const { src, alt, title, width, height } = node.attrs;
  checkImageProps({ src, alt, title });
  checkDimensions({ width, height });
  const props = { src, alt, title };
  if (width != null) props.width = width;
  if (height != null) props.height = height;
  return { id: node.attrs.relaymarkId, type: "image", props, content: [] };
}
function checkImageProps({ src, alt, title }) {
  if (!safeImageSource(src)) throw new TypeError("Image src must be durable local media or HTTPS");
  for (const [name, value] of [["alt", alt], ["title", title]]) {
    if (value !== null && (typeof value !== "string" || value.length > 4096 || /[\r\n]/u.test(value))) {
      throw new TypeError(`Invalid image ${name}`);
    }
  }
}
function mapEntityReference(node, seen) {
  checkNode(
    node,
    "relayEntityReference",
    seen,
    ["entityRef", "entityId", "entityType", "label", "projection", "source"]
  );
  if (node.content !== void 0 && children(node, "relayEntityReference").length !== 0) {
    throw new TypeError("Entity reference atom cannot have children");
  }
  const { entityRef, entityId: id2, entityType: entityType2, label, projection, source } = node.attrs;
  const authored = parseEntityReferenceSource(source);
  if (!authored || authored.id !== entityRef || authored.entityId !== id2 || entityType2 !== "Entity" || authored.label !== label || authored.projection !== projection) {
    throw new TypeError("Entity reference source/identity mismatch");
  }
  return {
    id: node.attrs.relaymarkId,
    type: "relay.entity_reference",
    props: { id: entityRef, label, projection, source },
    content: []
  };
}
var paperControlFields = { button: ["label", "kind", "target"], anchor: ["name"], connection: ["provider"] };
function mapPaperControl(node, seen) {
  const control = paperControlKind(node.type);
  checkNode(node, node.type, seen, paperControlFields[control]);
  if (node.content !== void 0 && children(node, node.type).length !== 0) {
    throw new TypeError("Paper control cannot have children");
  }
  const authored = Object.fromEntries(paperControlFields[control].map((field) => [field, node.attrs[field]]));
  const source = canonicalPaperControlSource(control, authored);
  return {
    id: node.attrs.relaymarkId,
    type: "relay.paper_control",
    props: { control, ...authored, source },
    content: []
  };
}
function mapAgentSuggestion(node, seen) {
  checkNode(node, "agentSuggestion", seen, ["review", "kind", "confidence", "evidence", "content"]);
  if (node.content !== void 0 && children(node, "agentSuggestion").length !== 0) {
    throw new TypeError("AgentSuggestion atom cannot have children");
  }
  const { review, kind, confidence, evidence, content: content2 } = assertAgentSuggestion(
    node.attrs.review,
    node.attrs.kind,
    node.attrs.confidence,
    node.attrs.evidence,
    node.attrs.content
  );
  return {
    id: node.attrs.relaymarkId,
    type: "relay.agent_suggestion",
    props: { review, kind, evidence, ...confidence === null ? {} : { confidence } },
    content: [{ type: "text", text: content2 }]
  };
}
var videoId = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;
function checkVideoId(value) {
  if (typeof value !== "string" || !videoId.test(value)) {
    throw new TypeError("Video ID must be a canonical lowercase UUID");
  }
}
function mapVideo(node, seen) {
  checkNode(node, "videoEmbed", seen, ["videoId"]);
  if (node.content !== void 0 && children(node, "videoEmbed").length !== 0) {
    throw new TypeError("Video cannot have children");
  }
  checkVideoId(node.attrs.videoId);
  return {
    id: node.attrs.relaymarkId,
    type: "relay.video_embed",
    props: { videoId: node.attrs.videoId },
    content: []
  };
}
function mapTable(node, seen) {
  checkNode(node, "table", seen);
  return { id: node.attrs.relaymarkId, type: "table", content: children(node, "table", 1).map((row) => mapRow(row, seen)) };
}
function mapRow(node, seen) {
  checkNode(node, "tableRow", seen);
  return { id: node.attrs.relaymarkId, type: "table_row", content: children(node, "tableRow", 1).map((cell) => mapCell(cell, seen)) };
}
function mapCell(node, seen) {
  assertObject(node, "table cell");
  if (node.type !== "tableCell" && node.type !== "tableHeader") {
    throw new TypeError(`Unsupported table child: ${String(node.type)}`);
  }
  checkNode(node, node.type, seen, ["colspan", "rowspan", "colwidth", "align"]);
  const { colspan, rowspan, colwidth, align } = node.attrs;
  checkCellProps({ colspan, rowspan, colwidth, align });
  return {
    id: node.attrs.relaymarkId,
    type: "table_cell",
    props: { header: node.type === "tableHeader", colspan, rowspan, colwidth, align },
    content: children(node, node.type, 1).map((child) => mapBlock(child, seen, 0))
  };
}
function mapParagraph(node, seen) {
  checkNode(node, "paragraph", seen);
  return { id: node.attrs.relaymarkId, type: "paragraph", content: inlineChildren(node, "paragraph").map(mapInline) };
}
function mapText(node) {
  assertObject(node, "text");
  onlyKeys(node, ["type", "text"], "text");
  requireType(node, "text");
  if (typeof node.text !== "string" || node.text.length === 0) {
    throw new TypeError("Text must be a nonempty string");
  }
  return { type: "text", text: node.text };
}
function checkNode(node, type, seen, additionalAttrs = []) {
  assertObject(node, type);
  onlyKeys(node, ["type", "attrs", "content"], type);
  requireType(node, type);
  assertObject(node.attrs, `${type}.attrs`);
  onlyKeys(node.attrs, ["relaymarkId", ...additionalAttrs], `${type}.attrs`);
  checkId(node.attrs.relaymarkId, seen);
}
function checkCellProps(props) {
  if (!Number.isSafeInteger(props.colspan) || props.colspan < 1 || !Number.isSafeInteger(props.rowspan) || props.rowspan < 1) {
    throw new TypeError("Cell spans must be positive safe integers");
  }
  if (props.colwidth !== null && (!Array.isArray(props.colwidth) || props.colwidth.length !== props.colspan || props.colwidth.some((width) => !Number.isSafeInteger(width) || width < 0))) {
    throw new TypeError("Cell colwidth must be null or one non-negative width per spanned column");
  }
  if (!alignments.has(props.align)) {
    throw new TypeError("Cell align must be null, left, center, or right");
  }
}
function checkId(id2, seen) {
  if (typeof id2 !== "string" || !blockId.test(id2)) throw new TypeError("Missing or invalid relaymarkId");
  if (seen.has(id2)) throw new TypeError(`Duplicate relaymarkId: ${id2}`);
  seen.add(id2);
}
function children(node, label, minimum = 0) {
  if (!Array.isArray(node.content) || node.content.length < minimum) {
    throw new TypeError(`${label} requires an array of at least ${minimum} children`);
  }
  return node.content;
}
function inlineChildren(node, label) {
  if (node.content === void 0) return [];
  return children(node, label);
}
function validateGrid(table) {
  const rows = table.content;
  if (rows.length > maxRows || rows.reduce((count, row) => count + row.content.length, 0) > maxCells) {
    throw new TypeError("Table exceeds the draft row/cell limit");
  }
  const occupied = [];
  let expectedWidth;
  for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    const slots = occupied[rowIndex] || [];
    let column = 0;
    for (const cell of rows[rowIndex].content) {
      while (slots[column]) column++;
      const { colspan, rowspan } = cell.props;
      if (colspan > maxColumns || column + colspan > maxColumns) {
        throw new TypeError("Table exceeds the draft column limit");
      }
      if (rowIndex + rowspan > rows.length) throw new TypeError("Cell rowspan exceeds table rows");
      for (let r = rowIndex; r < rowIndex + rowspan; r++) {
        occupied[r] || (occupied[r] = []);
        for (let c = column; c < column + colspan; c++) {
          if (occupied[r][c]) throw new TypeError("Overlapping table cells");
          occupied[r][c] = true;
        }
      }
      column += colspan;
    }
    const width = occupied[rowIndex].length;
    if (expectedWidth === void 0) expectedWidth = width;
    if (width !== expectedWidth || Array.from({ length: width }, (_, c) => occupied[rowIndex][c]).some((slot) => !slot)) {
      throw new TypeError("Table rows must form a complete rectangle");
    }
  }
}
function requireType(node, type) {
  if (node.type !== type) throw new TypeError(`Expected ${type}, got ${String(node.type)}`);
}
function assertObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${label} must be an object`);
  }
}
function onlyKeys(object4, allowed, label) {
  for (const key2 of Object.keys(object4)) {
    if (!allowed.includes(key2)) throw new TypeError(`Unsupported ${label} field: ${key2}`);
  }
}
function checkDimensions(props) {
  for (const key2 of ["width", "height"]) {
    const value = props[key2];
    if (value != null && (!Number.isSafeInteger(value) || value <= 0)) throw new TypeError("Image dimensions must be positive safe integers");
  }
}
var questionFields = ["id", "type", "required", "points", "min", "max", "settings"];
var optionFields = ["id", "correct", "points", "settings"];
var questionTypes = /* @__PURE__ */ new Set(["short_text", "long_text", "email", "phone", "number", "multiple_choice", "checkboxes", "dropdown", "linear_scale", "date", "file_upload", "page_break", "single_select", "multi_select", "entity_ref", "file", "slot_picker", "hidden_field", "calculated_field", "video_question", "video_response", "payment", "payment_block", "lightning_payment"]);
function validateQuestionProps(props, option = false) {
  assertObject(props, "form authored props");
  onlyKeys(props, option ? optionFields : questionFields, "form authored props");
  if (typeof props.id !== "string" || !props.id.trim() || /[\r\n\u0000]/u.test(props.id)) throw new TypeError("Invalid form identity");
  if (option ? typeof props.correct !== "boolean" : !questionTypes.has(props.type) || typeof props.required !== "boolean") throw new TypeError("Invalid form type or boolean");
  for (const key2 of option ? ["points"] : ["points", "min", "max"]) {
    if (props[key2] != null && (typeof props[key2] !== "number" || !Number.isFinite(props[key2]))) throw new TypeError("Invalid form numeric setting");
  }
  assertObject(props.settings, "form authored settings");
  validateJSONValue(props.settings);
}
function validateJSONValue(value, depth = 0) {
  if (depth > 32) throw new TypeError("Authored settings nesting exceeds bound");
  if (value === null || typeof value === "string" || typeof value === "boolean") return;
  if (typeof value === "number" && Number.isFinite(value)) return;
  if (Array.isArray(value)) {
    value.forEach((item) => validateJSONValue(item, depth + 1));
    return;
  }
  if (value && Object.getPrototypeOf(value) === Object.prototype) {
    Object.values(value).forEach((item) => validateJSONValue(item, depth + 1));
    return;
  }
  throw new TypeError("Authored settings must contain only portable JSON");
}
function formProps(attrs, option) {
  const defaults = option ? { correct: false, points: null, settings: {} } : { required: false, points: null, min: null, max: null, settings: {} };
  const result = { ...defaults };
  for (const key2 of option ? optionFields : questionFields) if (attrs[key2] !== void 0) result[key2] = attrs[key2];
  validateQuestionProps(result, option);
  return result;
}
function mapQuestion(node, seen) {
  checkNode(node, "questionBlock", seen, questionFields);
  const props = formProps(node.attrs, false), parts = children(node, "questionBlock", 1);
  checkNode(parts[0], "questionLabel", seen);
  const label = { id: parts[0].attrs.relaymarkId, type: "paragraph", content: inlineChildren(parts[0], "questionLabel").map(mapInline) };
  const optionIDs = /* @__PURE__ */ new Set();
  const options = parts.slice(1).map((option) => {
    checkNode(option, "questionOption", seen, optionFields);
    const props2 = formProps(option.attrs, true);
    if (optionIDs.has(props2.id)) throw new TypeError("Duplicate option identity");
    optionIDs.add(props2.id);
    return { id: option.attrs.relaymarkId, type: "relay.form_option", props: props2, content: inlineChildren(option, "questionOption").map(mapInline) };
  });
  return { id: node.attrs.relaymarkId, type: "relay.form_question", props, content: [label, ...options] };
}
var dataViewFields = ["source", "projection", "columns", "filter", "sort", "group", "limit", "title"];
function dataViewProps(attrs) {
  const props = {};
  for (const key2 of dataViewFields) if (attrs[key2] != null) props[key2] = attrs[key2];
  if (typeof props.source !== "string" || !/^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/u.test(props.source) || !["list", "table", "feed", "calendar", "kanban", "chart"].includes(props.projection)) throw new TypeError("Invalid data view source/projection");
  for (const key2 of ["columns", "sort"]) if (props[key2] !== void 0 && (!Array.isArray(props[key2]) || props[key2].some((v) => typeof v !== "string"))) throw new TypeError("Invalid data view keys");
  if (props.filter !== void 0) {
    assertObject(props.filter, "data view filter");
    const scalar = (v) => v === null || typeof v === "string" || typeof v === "boolean" || typeof v === "number" && Number.isFinite(v);
    for (const [key2, value] of Object.entries(props.filter)) if (!/^[a-z][a-z0-9_]*$/u.test(key2) || !(scalar(value) || Array.isArray(value) && value.every(scalar))) throw new TypeError("Invalid declarative data view filter");
  }
  if (props.group !== void 0 && (typeof props.group !== "string" || !/^[a-z][a-z0-9_]*$/u.test(props.group))) throw new TypeError("Invalid data view group");
  if (props.limit !== void 0 && (!Number.isSafeInteger(props.limit) || props.limit < 1 || props.limit > 1e3)) throw new TypeError("Invalid data view limit");
  if (props.title !== void 0 && typeof props.title !== "string") throw new TypeError("Invalid data view title");
  return props;
}
function mapDataView(node, seen) {
  checkNode(node, "relayDataView", seen, dataViewFields);
  if (node.content !== void 0 && children(node, "relayDataView").length) throw new TypeError("Data view cannot carry records/children");
  return { id: node.attrs.relaymarkId, type: "relay.data_view", props: dataViewProps(node.attrs), content: [] };
}
function assertAuthoredMetadata(value) {
  assertObject(value, "authored metadata");
  onlyKeys(value, ["frontmatter", "annotations", "resources", "meta"], "authored metadata");
  for (const key2 of ["frontmatter", "meta"]) if (Object.hasOwn(value, key2)) assertObject(value[key2], key2);
  for (const key2 of ["annotations", "resources"]) if (Object.hasOwn(value, key2) && !Array.isArray(value[key2])) throw TypeError(`Invalid ${key2}`);
  let budget2 = 1e6;
  const visit = (value2, depth) => {
    if (--budget2 < 0 || depth > 128) throw TypeError("Authored metadata resource limit");
    if (value2 === null || typeof value2 === "string" || typeof value2 === "boolean") return;
    if (typeof value2 === "number" && Number.isFinite(value2)) return;
    if (Array.isArray(value2)) {
      value2.forEach((child) => visit(child, depth + 1));
      return;
    }
    if (value2 && typeof value2 === "object" && (Object.getPrototypeOf(value2) === Object.prototype || Object.getPrototypeOf(value2) === null)) {
      for (const item of Object.values(value2)) visit(item, depth + 1);
      return;
    }
    throw TypeError("Invalid authored metadata JSON");
  };
  visit(value, 0);
  return value;
}

// src/canonical-json.js
function stableStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }
  if (value && typeof value === "object") {
    const entries = Object.entries(value).filter(([, item]) => item !== void 0).sort(([a], [b]) => a.localeCompare(b));
    return `{${entries.map(([key2, item]) => `${JSON.stringify(key2)}:${stableStringify(item)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}
function cloneCanonicalJSON(value) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (Array.isArray(value)) return value.map(cloneCanonicalJSON);
  if (value && (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null)) return Object.fromEntries(Object.entries(value).map(([key2, item]) => [key2, cloneCanonicalJSON(item)]));
  throw new TypeError("Invalid authored JSON value");
}

// src/owned-command-group.js
function canonicalOperationID(value) {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value)) throw TypeError("Invalid owned operation UUID");
  return value;
}
function validateOwnedCommandGroup(value) {
  if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).some((k) => !["owner_id", "reference", "operation_ids"].includes(k)) || !Array.isArray(value.operation_ids) || value.operation_ids.length < 1 || value.operation_ids.length > 4096) throw TypeError("Invalid maintained command group");
  canonicalOperationID(value.owner_id);
  value.operation_ids.forEach(canonicalOperationID);
  if (value.reference !== value.operation_ids[0] || new Set(value.operation_ids).size !== value.operation_ids.length) throw TypeError("Invalid maintained command membership");
  return value;
}
function validateOwnedHistory(value) {
  if (!value || !["undo", "redo"].includes(value.kind) || Object.keys(value).some((k) => !["kind", "owner_id", "reference", "operation_ids"].includes(k))) throw TypeError("Invalid owned history");
  validateOwnedCommandGroup({ owner_id: value.owner_id, reference: value.reference, operation_ids: value.operation_ids });
  return value;
}

// src/content-edit.js
import { EditorState, Selection } from "prosemirror-state";
import { newlineInCode, createParagraphNear, liftEmptyBlock, splitBlockKeepMarks } from "prosemirror-commands";
import { splitListItemKeepMarks, sinkListItem, liftListItem } from "prosemirror-schema-list";
import * as tableCommands from "prosemirror-tables";

// src/document-snapshot.js
var schema = createCanonicalEditorSchema();

// src/content-edit-witness.js
var schema2 = createCanonicalEditorSchema();

// src/content-edit-write.js
function contentEditTextGroups(document2) {
  const groups = [];
  function visit(node, position) {
    let groupIndex = 0, group = null;
    node.forEach((child, offset) => {
      const start = (node.type.name === "doc" ? 0 : position + 1) + offset;
      if (child.isText) {
        if (!group) {
          group = { parent: node.attrs.relaymarkId, index: groupIndex++, position: start, text: "" };
          groups.push(group);
        }
        group.text += child.text;
      } else {
        group = null;
        visit(child, start);
        groupIndex++;
      }
    });
    if (node.inlineContent && node.content.size === 0) groups.push({ parent: node.attrs.relaymarkId, index: 0, position: position + 1, text: "" });
  }
  visit(document2, -1);
  return groups;
}
function boundary(text, offset) {
  if (offset > 0 && offset < text.length) {
    const a = text.charCodeAt(offset - 1), b = text.charCodeAt(offset);
    if (a >= 55296 && a <= 56319 && b >= 56320 && b <= 57343) throw TypeError("Causal writer boundary splits Unicode");
  }
}
function planContentEditTextWrite(prepared, sourceParent, sourceGroup, targetParent, targetGroup, sourceSpan) {
  let source = prepared.before_groups[sourceParent + ":" + sourceGroup], target = prepared.after_groups[targetParent + ":" + targetGroup];
  if (!source || !target) throw TypeError("Causal writer text group unavailable");
  if (sourceSpan !== void 0) {
    if (!sourceSpan || Object.keys(sourceSpan).sort().join(",") !== "length,offset" || !Number.isSafeInteger(sourceSpan.offset) || !Number.isSafeInteger(sourceSpan.length) || sourceSpan.offset < 0 || sourceSpan.length < 0 || sourceSpan.offset + sourceSpan.length > source.text.length) throw TypeError("Invalid causal source branch span");
    boundary(source.text, sourceSpan.offset);
    boundary(source.text, sourceSpan.offset + sourceSpan.length);
    source = { ...source, position: source.position + sourceSpan.offset, text: source.text.slice(sourceSpan.offset, sourceSpan.offset + sourceSpan.length) };
  }
  const kept = [];
  let lower = 0, upper = prepared.retained_ranges.length;
  while (lower < upper) {
    const middle = lower + upper >>> 1, range = prepared.retained_ranges[middle];
    if (range.source_from + range.length <= source.position) lower = middle + 1;
    else upper = middle;
  }
  for (let i = lower; i < prepared.retained_ranges.length && prepared.retained_ranges[i].source_from < source.position + source.text.length; i++) {
    const range = prepared.retained_ranges[i];
    const from2 = Math.max(range.source_from, source.position, range.source_from + target.position - range.destination_from);
    const to2 = Math.min(range.source_from + range.length, source.position + source.text.length, range.source_from + target.position + target.text.length - range.destination_from);
    if (from2 < to2) kept.push({ source: from2 - source.position, target: range.destination_from + from2 - range.source_from - target.position, count: to2 - from2 });
  }
  kept.sort((a, b) => a.target - b.target);
  const delta = [];
  let from = 0, to = 0;
  function gaps(nextSource, nextTarget) {
    boundary(source.text, from);
    boundary(source.text, nextSource);
    boundary(target.text, to);
    boundary(target.text, nextTarget);
    if (nextSource < from || nextTarget < to) throw TypeError("Causal writer retention order disagrees");
    if (nextSource > from) delta.push({ delete: nextSource - from });
    if (nextTarget > to) delta.push({ insert: target.text.slice(to, nextTarget) });
  }
  for (const range of kept) {
    gaps(range.source, range.target);
    boundary(source.text, range.source + range.count);
    boundary(target.text, range.target + range.count);
    if (source.text.slice(range.source, range.source + range.count) !== target.text.slice(range.target, range.target + range.count)) throw TypeError("Causal writer retained contents disagree");
    delta.push({ retain: range.count });
    from = range.source + range.count;
    to = range.target + range.count;
  }
  gaps(source.text.length, target.text.length);
  return delta;
}

// src/content-edit.js
var schema3 = createCanonicalEditorSchema();
function applyContentEdit(admittedDocument, operation, { maximumSteps = 512 } = {}) {
  if (!operation || operation.kind !== "content_edit" || !Array.isArray(operation.steps) || !Number.isSafeInteger(maximumSteps) || maximumSteps < 1 || maximumSteps > 4096 || operation.steps.length < 1 || operation.steps.length > maximumSteps)
    throw new TypeError("Invalid or oversized canonical content edit");
  if (operation.group && operation.history) throw TypeError("Command group and inverse history are exclusive");
  if (operation.group) validateOwnedCommandGroup(operation.group);
  if (operation.history) validateOwnedHistory(operation.history);
  proseMirrorToRelayMark(admittedDocument);
  let document2 = schema3.nodeFromJSON(admittedDocument);
  document2.check();
  const step_maps = [];
  const originalIdentities = /* @__PURE__ */ new Map();
  document2.descendants((node, position) => {
    const id2 = node.attrs.relaymarkId;
    if (!id2) return;
    if (originalIdentities.has(id2)) throw TypeError("Ambiguous retained subtree identity");
    originalIdentities.set(id2, { node, position });
  });
  let copied_subtree_ranges = [];
  let retained_ranges = document2.content.size ? [{ source_from: 0, destination_from: 0, length: document2.content.size }] : [];
  for (const json2 of operation.steps) {
    if (json2.stepType === "docAttr") {
      if (json2.attr !== "relaymark") throw TypeError("Unknown canonical document attribute");
      assertAuthoredMetadata(json2.value);
    }
    const step = Step.fromJSON(schema3, json2);
    if (stableStringify(step.toJSON()) !== stableStringify(json2)) throw new TypeError("Noncanonical content edit step");
    const result = step.apply(document2);
    if (result.failed) throw new TypeError("Canonical content edit refused: " + result.failed);
    document2 = result.doc;
    const map = step.getMap();
    step_maps.push({ ranges: [...map.ranges], inverted: map.inverted });
    const changed = [];
    map.forEach((from, to) => changed.push([from, to]));
    const mapRanges = (ranges) => {
      const next2 = [];
      for (const range of ranges) {
        const start = range.destination_from, end = start + range.length;
        const boundaries = [start, end, ...changed.flatMap(([from, to]) => [from, to]).filter((p) => p > start && p < end)].sort((a, b) => a - b);
        for (let i = 1; i < boundaries.length; i++) {
          const from = boundaries[i - 1], to = boundaries[i];
          if (from === to || changed.some(([a, b]) => a < b && from >= a && to <= b)) continue;
          const destination = map.map(from, 1), upper = map.map(to, -1);
          if (upper - destination !== to - from) throw new TypeError("Unprovable maintained map interval");
          const source = range.source_from + from - start, last = next2.at(-1);
          if (last && last.source_from + last.length === source && last.destination_from + last.length === destination) last.length += to - from;
          else next2.push({ source_from: source, destination_from: destination, length: to - from });
          if (next2.length > 65536) throw new TypeError("Content edit causal mapping budget exceeded");
        }
      }
      return next2;
    };
    copied_subtree_ranges = mapRanges(copied_subtree_ranges);
    const candidates = [];
    if (json2.stepType === "replace" && step.slice) {
      step.slice.content.descendants((node, pos) => {
        const id2 = node.attrs.relaymarkId, original = id2 && originalIdentities.get(id2);
        if (!original || !node.eq(original.node)) return;
        const destination = step.from + pos - step.slice.openStart;
        if (destination < 0 || !document2.nodeAt(destination)?.eq(node)) return;
        if (candidates.some((range) => destination >= range.destination_from && destination + node.nodeSize <= range.destination_from + range.length)) return false;
        candidates.push({ source_from: original.position, destination_from: destination, length: node.nodeSize });
        return false;
      });
    }
    copied_subtree_ranges.push(...candidates);
    if (copied_subtree_ranges.length > 65536) throw TypeError("Copied subtree mapping budget exceeded");
    const next = mapRanges(retained_ranges);
    retained_ranges = next;
  }
  document2.check();
  const json = JSON.parse(JSON.stringify(document2.toJSON()));
  const authored_document = proseMirrorToRelayMark(json);
  const inserted_ranges = [];
  let cursor = 0;
  for (const range of retained_ranges.slice().sort((a, b) => a.destination_from - b.destination_from)) {
    if (range.destination_from > cursor) inserted_ranges.push({ destination_from: cursor, length: range.destination_from - cursor });
    cursor = Math.max(cursor, range.destination_from + range.length);
  }
  if (cursor < document2.content.size) inserted_ranges.push({ destination_from: cursor, length: document2.content.size - cursor });
  return { document: json, authored_document, step_maps, retained_ranges, inserted_ranges, copied_subtree_ranges };
}
function prepareContentEditWrite(before, steps, after) {
  const expected = applyContentEdit(before, { kind: "content_edit", steps });
  if (stableStringify(expected.document) !== stableStringify(after)) throw TypeError("Causal writer result disagrees with actual steps");
  const groups = (document2) => Object.fromEntries(contentEditTextGroups(schema3.nodeFromJSON(document2)).map((group) => [group.parent + ":" + group.index, group]));
  const prepared = { retained_ranges: expected.retained_ranges, before_groups: groups(before), after_groups: groups(after) };
  const causal_targets = [];
  for (const target of Object.values(prepared.after_groups)) {
    const source = prepared.before_groups[target.parent + ":" + target.index];
    let retained = false;
    if (source && source.text.length === target.text.length) {
      if (!source.text.length) retained = true;
      else {
        let lower = 0, upper = prepared.retained_ranges.length;
        while (lower < upper) {
          const middle = lower + upper >>> 1, range2 = prepared.retained_ranges[middle];
          if (range2.source_from + range2.length <= source.position) lower = middle + 1;
          else upper = middle;
        }
        const range = prepared.retained_ranges[lower];
        retained = !!range && range.source_from <= source.position && range.source_from + range.length >= source.position + source.text.length && range.destination_from + source.position - range.source_from === target.position;
      }
    }
    if (!retained) causal_targets.push(target.parent);
  }
  return { ...prepared, causal_targets: [...new Set(causal_targets)] };
}
function createContentEditWrite(before, steps, after) {
  const prepared = prepareContentEditWrite(before.toJSON(), steps, after.toJSON());
  const targets = new Set(prepared.causal_targets), needed = /* @__PURE__ */ new WeakMap();
  function visit(node) {
    let changed = targets.has(node.attrs.relaymarkId);
    node.forEach((child) => {
      if (visit(child)) changed = true;
    });
    needed.set(node, changed);
    return changed;
  }
  visit(after);
  return { requiresWrite: (node) => needed.get(node) === true, planText: (sourceParent, sourceGroup, targetParent, targetGroup, sourceSpan) => planContentEditTextWrite(prepared, sourceParent, sourceGroup, targetParent, targetGroup, sourceSpan) };
}

// node_modules/lib0/webcrypto.js
var subtle = crypto.subtle;
var getRandomValues = crypto.getRandomValues.bind(crypto);

// node_modules/lib0/random.js
var uint32 = () => getRandomValues(new Uint32Array(1))[0];
var uuidv4Template = "10000000-1000-4000-8000" + -1e11;
var uuidv4 = () => uuidv4Template.replace(
  /[018]/g,
  /** @param {number} c */
  (c) => (c ^ uint32() & 15 >> c / 4).toString(16)
);

// adapters/collaboration/owned-command-group.js
var key = "relaymark:operation_ids";
var owners = /* @__PURE__ */ new WeakMap();
function bindOwnedHistoryOwner(manager, ownerID) {
  canonicalOperationID(ownerID);
  if (!manager || !Array.isArray(manager.undoStack) || !Array.isArray(manager.redoStack)) throw TypeError("Unavailable actual history owner");
  const existing = owners.get(manager);
  if (existing && existing !== ownerID) throw TypeError("Conflicting maintained history owner");
  for (const item of [...manager.undoStack, ...manager.redoStack]) {
    const group = item.meta?.get(key);
    if (group && validateOwnedCommandGroup(group).owner_id !== ownerID) throw TypeError("Conflicting maintained history owner");
  }
  owners.set(manager, ownerID);
  return ownerID;
}
function readOwnedHistoryOwner(manager) {
  return owners.get(manager) ?? bindOwnedHistoryOwner(manager, uuidv4());
}
function ownedGroup(manager, item) {
  const group = validateOwnedCommandGroup(item?.meta?.get(key));
  if (group.owner_id !== readOwnedHistoryOwner(manager)) throw TypeError("Conflicting maintained history owner");
  return group;
}
function freeze(group) {
  return Object.freeze({ ...group, operation_ids: Object.freeze(group.operation_ids.slice()) });
}
function bindOwnedCommandGroup(manager, event, operationID) {
  canonicalOperationID(operationID);
  const item = event?.stackItem;
  if (!manager || manager.undoing || manager.redoing || event.type !== "undo" || manager.undoStack.at(-1) !== item || !item?.meta) throw TypeError("Unavailable actual maintained command item");
  const ownerID = readOwnedHistoryOwner(manager), existing = item.meta.get(key), ids = existing ? ownedGroup(manager, item).operation_ids.slice() : [];
  for (const entry of [...manager.undoStack, ...manager.redoStack]) if (entry !== item && entry.meta.get(key) && ownedGroup(manager, entry).operation_ids.includes(operationID)) throw TypeError("Duplicate owned operation UUID");
  if (ids.at(-1) !== operationID) {
    if (ids.includes(operationID)) throw TypeError("Out-of-order owned operation UUID");
    ids.push(operationID);
  }
  const group = validateOwnedCommandGroup({ owner_id: ownerID, reference: ids[0], operation_ids: ids });
  item.meta.set(key, freeze(group));
  return group;
}
function readOwnedCommandGroup(manager, operationID) {
  canonicalOperationID(operationID);
  const item = manager?.undoStack.at(-1);
  if (!item?.meta.get(key)) throw TypeError("No actual owned command group");
  const group = ownedGroup(manager, item);
  if (group.operation_ids.at(-1) !== operationID) throw TypeError("No actual owned command group");
  return { ...group, operation_ids: group.operation_ids.slice() };
}
function bindOwnedCommandHistory(manager, event) {
  const undo = event?.type === "undo", redo = event?.type === "redo";
  if (!manager || event.origin !== manager || !(undo && manager.undoing || redo && manager.redoing)) throw TypeError("Unavailable actual maintained inverse");
  const inverse = (undo ? manager.redoStack : manager.undoStack).at(-1);
  if (!event.stackItem?.meta.get(key) || !inverse?.meta) throw TypeError("Unbound actual owned inverse");
  const group = ownedGroup(manager, event.stackItem);
  inverse.meta.set(key, freeze(group));
  return { kind: event.type, ...group, operation_ids: group.operation_ids.slice() };
}

// adapters/collaboration/content-edit-observer.js
import * as Y from "yjs";
var id = (value) => ({ client: value.client, clock: value.clock });
var optionalID = (value) => value ? id(value) : null;
function budget(maximumSteps) {
  if (!Number.isSafeInteger(maximumSteps) || maximumSteps < 1 || maximumSteps > 1e6) throw Error("Invalid observation budget");
  let remaining = maximumSteps;
  return () => {
    if (--remaining < 0) throw Error("Observation budget exhausted");
  };
}
function settled(doc) {
  if (!doc || doc.gc || doc.store.pendingStructs || doc.store.pendingDs) throw Error("Observation requires a settled retained owner");
}
function parent(item) {
  const branch = item.parent;
  if (!branch || typeof branch === "string" || branch instanceof Y.ID) throw Error("Unavailable retained parent");
  return branch._item ? { type: id(branch._item.id) } : { root: Y.findRootTypeKey(branch) };
}
function content(item, step) {
  step();
  const value = item.content;
  if (value instanceof Y.ContentString) return { kind: "string", text: value.str };
  if (value instanceof Y.ContentFormat) return { kind: "format", key: value.key, value: cloneCanonicalJSON(value.value) };
  if (value instanceof Y.ContentAny) return { kind: "any", values: cloneCanonicalJSON(value.arr) };
  if (value instanceof Y.ContentEmbed) return { kind: "embed", value: cloneCanonicalJSON(value.embed) };
  if (value instanceof Y.ContentJSON) return { kind: "json", values: value.arr.map((v) => JSON.stringify(cloneCanonicalJSON(v))) };
  if (value instanceof Y.ContentBinary) return { kind: "binary", bytes: [...value.content] };
  if (value instanceof Y.ContentType) {
    const branch = value.type;
    let type_kind, name = null;
    if (branch instanceof Y.XmlElement) {
      type_kind = "xml_element";
      name = branch.nodeName;
    } else if (branch instanceof Y.XmlText) type_kind = "xml_text";
    else if (branch instanceof Y.XmlFragment) type_kind = "xml_fragment";
    else if (branch instanceof Y.Text) type_kind = "text";
    else if (branch instanceof Y.Map) type_kind = "map";
    else if (branch instanceof Y.Array) type_kind = "array";
    else throw Error("Unsupported retained type");
    return { kind: "type", type_kind, name };
  }
  throw Error("Unsupported or pruned retained content");
}
function captureContentEditSnapshot(root, { maximumSteps = 1e6 } = {}) {
  settled(root.doc);
  const step = budget(maximumSteps);
  function visit(branch, depth) {
    step();
    if (depth > 128) throw Error("Observation depth exceeded");
    if (branch._item?.deleted) throw Error("Unavailable XML branch");
    if (branch instanceof Y.XmlText) {
      if (Object.keys(branch.getAttributes()).length) throw Error("Unsupported XML text attributes");
      const attributes = {}, runs = [];
      for (let item = branch._start; item; item = item.right) {
        step();
        if (item.deleted) continue;
        if (item.content instanceof Y.ContentFormat) {
          if (item.content.value === null) delete attributes[item.content.key];
          else attributes[item.content.key] = cloneCanonicalJSON(item.content.value);
          continue;
        }
        if (!(item.content instanceof Y.ContentString)) throw Error("Unsupported visible text content");
        runs.push({ item: id(item.id), count: item.length, text: item.content.str, attributes: cloneCanonicalJSON(attributes) });
      }
      if (!branch._item) throw Error("Unavailable XML text identity");
      return { kind: "text", type: id(branch._item.id), runs };
    }
    if (!(branch instanceof Y.XmlFragment)) throw Error("Unsupported XML branch");
    const children2 = [];
    for (let item = branch._start; item; item = item.right) {
      step();
      if (item.deleted) continue;
      if (!(item.content instanceof Y.ContentType)) throw Error("Unsupported XML child");
      children2.push(visit(item.content.type, depth + 1));
    }
    if (branch instanceof Y.XmlElement) {
      if (!branch._item) throw Error("Unavailable XML element identity");
      return { kind: "element", type: id(branch._item.id), name: branch.nodeName, attributes: cloneCanonicalJSON(branch.getAttributes()), children: children2 };
    }
    return { kind: "fragment", root: Y.findRootTypeKey(branch), children: children2 };
  }
  const result = visit(root, 0), metadata = root.doc.share.get("relaymark");
  if (metadata) {
    if (!(metadata instanceof Y.Map)) throw Error("Unsupported authored metadata root");
    const value = cloneCanonicalJSON(metadata.toJSON());
    if (Object.keys(value).length) result.metadata = value;
  }
  return result;
}
function captureContentEditFootprint(doc, bytes2, { maximumSteps = 1e6 } = {}) {
  settled(doc);
  if (!(bytes2 instanceof Uint8Array) || bytes2.length > 8 * 1024 * 1024) throw Error("Invalid original update bytes");
  const step = budget(maximumSteps);
  let decoder;
  class CheckedDecoder extends Y.UpdateDecoderV1 {
    constructor(value) {
      super(value);
      decoder = this;
    }
  }
  const decoded = Y.decodeUpdateV2(bytes2, CheckedDecoder);
  if (decoder.restDecoder.pos !== bytes2.length) throw Error("Trailing original update bytes");
  const current = Y.decodeStateVector(Y.encodeStateVector(doc));
  const structs = decoded.structs.map((item) => {
    step();
    if (!(item instanceof Y.Item) || !Number.isSafeInteger(item.id.clock + item.length) || item.id.clock + item.length > 2 ** 32 || item.id.clock + item.length > (current.get(item.id.client) || 0)) throw Error("Unavailable original update item");
    const stored = Y.getItem(doc.store, item.id);
    if (!(stored instanceof Y.Item)) throw Error("Unavailable retained item");
    return { item: id(item.id), count: item.length, parent: parent(stored), key: stored.parentSub ?? null, origin: optionalID(item.origin), right_origin: optionalID(item.rightOrigin), content: content(item, step), deleted: stored.deleted };
  }).sort((a, b) => a.item.client - b.item.client || a.item.clock - b.item.clock);
  const declared_deletes = [], deleted_items = [];
  for (const [client, ranges] of [...decoded.ds.clients].sort((a, b) => a[0] - b[0])) for (const range of ranges) {
    step();
    const end = range.clock + range.len;
    if (!Number.isSafeInteger(end) || range.len < 1 || end > 2 ** 32) throw Error("Invalid declared delete");
    declared_deletes.push({ item: { client, clock: range.clock }, count: range.len });
    for (let clock = range.clock; clock < end; ) {
      step();
      const stored = Y.getItem(doc.store, Y.createID(client, clock));
      if (!(stored instanceof Y.Item) || !stored.deleted) throw Error("Unavailable declared deletion");
      const next = Math.min(end, stored.id.clock + stored.length);
      if (next <= clock) throw Error("Invalid retained deletion");
      deleted_items.push({ item: { client, clock }, count: next - clock, stored_item: id(stored.id), stored_count: stored.length, parent: parent(stored), key: stored.parentSub ?? null, content: content(stored, step) });
      clock = next;
    }
  }
  return { state_vector: [...current].sort((a, b) => a[0] - b[0]).map(([client, clock]) => ({ client, clock })), structs, declared_deletes, deleted_items };
}

// adapters/collaboration/owned-history-branches.js
import * as Y2 from "yjs";
var installed = /* @__PURE__ */ new WeakMap();
function protectOwnedHistoryBranches(manager) {
  if (installed.has(manager)) return installed.get(manager);
  if (manager?.supportsUndoDeleteContext !== true) throw TypeError("Maintained UndoManager deletion context is unavailable");
  const previous = manager.deleteFilter, contexts = /* @__PURE__ */ new WeakMap();
  manager.deleteFilter = (item, context) => {
    let protectedItems = contexts.get(context);
    if (!protectedItems) {
      protectedItems = protectedSkeleton(context.itemsToDelete);
      contexts.set(context, protectedItems);
    }
    return !protectedItems.has(item) && previous(item, context);
  };
  const release = () => {
    manager.deleteFilter = previous;
    installed.delete(manager);
  };
  installed.set(manager, release);
  return release;
}
function protectedSkeleton(items) {
  const owned = new Set(items), protectedItems = /* @__PURE__ */ new Set();
  const xml = (item) => item.content instanceof Y2.ContentType && (item.content.type instanceof Y2.XmlElement || item.content.type instanceof Y2.XmlText);
  const roots = items.filter((item) => xml(item) && !hasOwnedAncestor(item));
  function hasOwnedAncestor(item) {
    let parent2 = item.parent;
    while (parent2?._item) {
      if (owned.has(parent2._item) && xml(parent2._item)) return true;
      parent2 = parent2._item.parent;
    }
    return false;
  }
  for (const root of roots) {
    const skeleton = /* @__PURE__ */ new Set([root]), pending = [root.content.type];
    let survivor = false;
    while (pending.length) {
      const branch = pending.pop();
      for (const item of branch._map.values()) {
        if (item.deleted) continue;
        skeleton.add(item);
        if (!owned.has(item)) survivor = true;
      }
      for (let item = branch._start; item; item = item.right) {
        if (item.deleted) continue;
        if (!owned.has(item)) survivor = true;
        if (xml(item)) {
          skeleton.add(item);
          pending.push(item.content.type);
        }
      }
    }
    if (survivor) for (const item of skeleton) protectedItems.add(item);
  }
  return protectedItems;
}

// adapters/collaboration/content-edit-mutation.js
var toBase64 = (bytes2) => (0, import_btoa.default)(Array.from(bytes2, (v) => String.fromCharCode(v)).join(""));
var fromBase64 = (value) => Uint8Array.from((0, import_atob.default)(value), (v) => v.charCodeAt(0));
var schema4 = createCanonicalEditorSchema();
var MAX_BYTES = 8 * 1024 * 1024;
var same = (a, b) => stableStringify(a) === stableStringify(b);
function fields2(value, allowed, required = allowed) {
  if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).some((k) => !allowed.includes(k)) || required.some((k) => !Object.hasOwn(value, k))) throw TypeError("Invalid mutation replay evidence");
}
function bytes(value) {
  if (typeof value !== "string" || value.length > 4 * Math.ceil(MAX_BYTES / 3)) throw TypeError("Invalid retained replay bytes");
  const result = fromBase64(value, { lastChunkHandling: "strict" });
  if (result.length > MAX_BYTES || toBase64(result) !== value) throw TypeError("Noncanonical retained replay bytes");
  return result;
}
function owner(state) {
  const doc = new Y3.Doc({ gc: false, guid: "relaymark:ephemeral-command-proof" });
  Y3.applyUpdate(doc, state);
  if (doc.store.pendingStructs || doc.store.pendingDs) throw TypeError("Unsettled retained replay state");
  for (const name of doc.share.keys()) if (!["default", "relaymark"].includes(name)) throw TypeError("Unknown retained replay root");
  if (!doc.share.has("default")) throw TypeError("Missing retained editor root");
  const root = doc.getXmlFragment("default");
  if (root._map.size) throw TypeError("Hidden editor root attributes");
  if (doc.share.has("relaymark")) doc.getMap("relaymark");
  captureContentEditSnapshot(doc.getXmlFragment("default"));
  return doc;
}
function fragment(content2, offset, count, total) {
  if (offset === 0 && count === total) return cloneCanonicalJSON(content2);
  if (content2.kind === "string") return { ...content2, text: content2.text.slice(offset, offset + count) };
  if (["any", "json"].includes(content2.kind)) return { ...content2, values: content2.values.slice(offset, offset + count) };
  throw TypeError("Unsupported retained item fragmentation");
}
function part(record, start, count) {
  const offset = start - record.item.clock;
  return { ...record, item: { client: record.item.client, clock: start }, count, origin: offset ? { client: record.item.client, clock: start - 1 } : record.origin, content: fragment(record.content, offset, count, record.count) };
}
function retainedPrefix(record, count, known) {
  let clock = record.item.clock, end = clock + count;
  const records = known.get(record.item.client) || [];
  let left = 0, right = records.length;
  while (left < right) {
    const mid = left + right >>> 1;
    if (records[mid].item.clock + records[mid].count <= clock) left = mid + 1;
    else right = mid;
  }
  for (let i = left; i < records.length; i++) {
    const saved = records[i];
    if (saved.item.clock > clock) break;
    const n = Math.min(end, saved.item.clock + saved.count) - clock, a = part(record, clock, n), b = part(saved, clock, n);
    delete a.deleted;
    delete b.deleted;
    if (!same(a, b)) throw TypeError("Original update rewrites retained item identity");
    clock += n;
    if (clock === end) return;
  }
  throw TypeError("Unavailable retained original prefix");
}
function intervals(ranges) {
  const result = [];
  for (const r of ranges.sort((a, b) => a.item.client - b.item.client || a.item.clock - b.item.clock)) {
    const prev = result.at(-1);
    if (prev && prev.item.client === r.item.client && prev.item.clock + prev.count >= r.item.clock) prev.count = Math.max(prev.item.clock + prev.count, r.item.clock + r.count) - prev.item.clock;
    else result.push(cloneCanonicalJSON(r));
  }
  return result;
}
function subtract(range, deleted) {
  let pieces = [range];
  for (const old of deleted) {
    if (old.item.client !== range.item.client) continue;
    pieces = pieces.flatMap((p) => {
      const a = p.item.clock, b = a + p.count, c = old.item.clock, d = c + old.count;
      if (c >= b || d <= a) return [p];
      return [...a < c ? [{ item: p.item, count: c - a }] : [], ...d < b ? [{ item: { client: p.item.client, clock: d }, count: b - d }] : []];
    });
  }
  return pieces;
}
function mergeRecords(records, withOrigins) {
  const out = [];
  for (const r of records.sort((a, b) => a.item.client - b.item.client || a.item.clock - b.item.clock)) {
    const p = out.at(-1);
    if (p && p.item.client === r.item.client && p.item.clock + p.count === r.item.clock && same(p.parent, r.parent) && p.key === r.key && p.deleted === r.deleted && p.content.kind === r.content.kind && ["string", "any", "json"].includes(r.content.kind) && (!withOrigins || same(p.right_origin, r.right_origin) && same(r.origin, { client: p.item.client, clock: r.item.clock - 1 }))) {
      p.count += r.count;
      if (p.content.kind === "string") p.content.text += r.content.text;
      else p.content.values.push(...r.content.values);
    } else out.push(cloneCanonicalJSON(r));
  }
  return out;
}
function normalized(footprint, before, known, deleted) {
  fields2(footprint, ["state_vector", "structs", "declared_deletes", "deleted_items"]);
  if (!Array.isArray(footprint.structs) || !Array.isArray(footprint.deleted_items) || !Array.isArray(footprint.declared_deletes) || footprint.structs.length + footprint.deleted_items.length + footprint.declared_deletes.length > 1e6) throw TypeError("Invalid original mutation footprint");
  const structs = [];
  for (const r of footprint.structs) {
    const prefix = Math.min(r.count, Math.max(0, (before.get(r.item.client) || 0) - r.item.clock));
    if (prefix) retainedPrefix(r, prefix, known);
    if (prefix < r.count) structs.push(part(r, r.item.clock + prefix, r.count - prefix));
  }
  const effective = intervals(footprint.declared_deletes.flatMap((r) => subtract(r, deleted))), deleted_items = [];
  for (const r of footprint.deleted_items) {
    for (const p of subtract({ item: r.item, count: r.count }, deleted)) {
      const offset = p.item.clock - r.stored_item.clock;
      deleted_items.push({ item: p.item, count: p.count, parent: r.parent, key: r.key, content: fragment(r.content, offset, p.count, r.stored_count) });
    }
  }
  return { state_vector: footprint.state_vector, structs: mergeRecords(structs, true), declared_deletes: effective, deleted_items: mergeRecords(deleted_items, false) };
}
function replayContentEditMutation(evidence) {
  if (evidence.operation?.history) return replayOwnedHistory(evidence);
  fields2(evidence, ["sender_state_base64", "current_state_base64", "writer_client", "operation", "footprint"]);
  const senderBytes = bytes(evidence.sender_state_base64), currentBytes = bytes(evidence.current_state_base64), sender = owner(senderBytes), current = owner(currentBytes);
  try {
    const before = Y3.decodeStateVector(Y3.encodeStateVector(current)), clients = /* @__PURE__ */ new Set();
    for (const r of evidence.footprint.structs ?? []) if (r.item.clock + r.count > (before.get(r.item.client) || 0)) clients.add(r.item.client);
    if (clients.size > 1 || (clients.size === 0 ? evidence.writer_client !== null : !clients.has(evidence.writer_client) || !Number.isSafeInteger(evidence.writer_client) || evidence.writer_client < 0)) throw TypeError("Replay writer must be independently observed from fresh structs");
    const initialized = initProseMirrorDoc(sender.getXmlFragment("default"), schema4), expected = applyContentEdit(initialized.doc.toJSON(), evidence.operation);
    let result = initialized.doc;
    for (const json of evidence.operation.steps) {
      const applied = Step2.fromJSON(schema4, json).apply(result);
      if (applied.failed) throw TypeError("Refused maintained command");
      result = applied.doc;
    }
    if (!same(result.toJSON(), expected.document)) throw TypeError("Maintained command execution disagrees");
    sender.clientID = evidence.writer_client ?? 0;
    const updates = [];
    sender.on("update", (update2) => updates.push(update2));
    initialized.meta.contentEditWrite = createContentEditWrite(initialized.doc, evidence.operation.steps, result);
    updateYFragment(sender, sender.getXmlFragment("default"), result, initialized.meta);
    if (updates.length !== 1) throw TypeError("Command must produce one maintained mutation transaction");
    const update = updates[0];
    const known = /* @__PURE__ */ new Map();
    for (const record of captureContentEditFootprint(current, currentBytes).structs) {
      const list = known.get(record.item.client) || [];
      list.push(record);
      known.set(record.item.client, list);
    }
    const ds = Y3.createDeleteSetFromStructStore(current.store), deleted = [];
    for (const [client, ranges] of ds.clients) for (const r of ranges) deleted.push({ item: { client, clock: r.clock }, count: r.len });
    Y3.applyUpdate(current, update);
    const footprint = captureContentEditFootprint(current, update), actual = normalized(evidence.footprint, before, known, deleted), replayed = normalized(footprint, before, known, deleted);
    if (!same(actual, replayed)) throw TypeError("Original mutation differs from executed maintained command");
    return { footprint, expected_update_base64: toBase64(update), complete_mutation_correspondence: true, retained_field_changes: fieldChanges(replayed) };
  } finally {
    sender.destroy();
    current.destroy();
  }
}
function observedWriter(footprint, doc) {
  const clocks = Y3.decodeStateVector(Y3.encodeStateVector(doc)), clients = /* @__PURE__ */ new Set();
  for (const item of footprint.structs) if (item.item.clock + item.count > (clocks.get(item.item.client) || 0)) clients.add(item.item.client);
  if (clients.size > 1) throw TypeError("Multiple actual command writers");
  return clients.size ? [...clients][0] : null;
}
function compareUpdate(current, originalFootprint, update) {
  const state = Y3.encodeStateAsUpdate(current), before = Y3.decodeStateVector(Y3.encodeStateVector(current)), known = /* @__PURE__ */ new Map();
  for (const record of captureContentEditFootprint(current, state).structs) {
    const list = known.get(record.item.client) || [];
    list.push(record);
    known.set(record.item.client, list);
  }
  const deleted = [];
  for (const [client, ranges] of Y3.createDeleteSetFromStructStore(current.store).clients) for (const r of ranges) deleted.push({ item: { client, clock: r.clock }, count: r.len });
  Y3.applyUpdate(current, update);
  const footprint = captureContentEditFootprint(current, update);
  if (!same(normalized(originalFootprint, before, known, deleted), normalized(footprint, before, known, deleted))) throw TypeError("Original mutation differs from maintained owned history");
  return { footprint, retained_field_changes: fieldChanges(normalized(footprint, before, known, deleted)) };
}
function fieldChanges(footprint) {
  const field = (r) => r.key !== null || r.content.kind === "format";
  return { allocated: footprint.structs.filter(field), deleted: footprint.deleted_items.filter(field) };
}
function redoneLinks(doc) {
  const result = /* @__PURE__ */ new Map();
  let remaining = 1e6;
  for (const structs of doc.store.clients.values()) for (const item of structs) {
    if (--remaining < 0) throw TypeError("Owned history observation budget exhausted");
    if (item instanceof Y3.Item) result.set(item.id.client + ":" + item.id.clock, item.redone ? item.redone.client + ":" + item.redone.clock : null);
  }
  return result;
}
function restoredCopies(doc, prior, links) {
  const copies = [], snapshot = captureContentEditSnapshot(doc.getXmlFragment("default")), visible = /* @__PURE__ */ new Set();
  let remaining = 1e6;
  function visit(node) {
    if (node.kind === "text") visible.add(node.type.client + ":" + node.type.clock);
    else for (const child of node.children) visit(child);
  }
  visit(snapshot);
  for (const structs of doc.store.clients.values()) for (const source of structs) {
    if (--remaining < 0) throw TypeError("Restored copy observation budget exhausted");
    if (!(source instanceof Y3.Item) || !(source.content instanceof Y3.ContentString) || !source.redone || source.id.clock >= (prior.get(source.id.client) || 0) || links.get(source.id.client + ":" + source.id.clock) === source.redone.client + ":" + source.redone.clock) continue;
    const destination = Y3.getItem(doc.store, source.redone);
    if (!(destination instanceof Y3.Item) || destination.id.clock > source.redone.clock || destination.id.clock + destination.length < source.redone.clock + source.length || !(destination.content instanceof Y3.ContentString) || destination.content.str.slice(source.redone.clock - destination.id.clock, source.redone.clock - destination.id.clock + source.length) !== source.content.str || !(source.parent instanceof Y3.XmlText) || !(destination.parent instanceof Y3.XmlText) || !source.parent._item || !destination.parent._item) throw TypeError("Unavailable exact maintained restored copy");
    if (destination.deleted || source.redone.clock < (prior.get(destination.id.client) || 0) || !visible.has(destination.parent._item.id.client + ":" + destination.parent._item.id.clock)) throw TypeError("Unreachable maintained restored copy");
    const selected = (item) => ({ runs: [{ type: { client: item.parent._item.id.client, clock: item.parent._item.id.clock }, item: { client: item.id.client, clock: item.id.clock }, count: item.length }] });
    const target = selected(destination);
    target.runs[0].item = { client: source.redone.client, clock: source.redone.clock };
    target.runs[0].count = source.length;
    copies.push({ source: selected(source), destination: target });
  }
  return copies;
}
function ownedTextAccounting(doc, before, copies) {
  const snapshot = captureContentEditSnapshot(doc.getXmlFragment("default")), fresh = [];
  function visit(node) {
    if (node.kind === "text") {
      for (const run of node.runs) {
        const start = Math.max(run.item.clock, before.get(run.item.client) || 0), count = run.item.clock + run.count - start;
        if (count > 0) fresh.push({ type: node.type, item: { client: run.item.client, clock: start }, count });
      }
    } else for (const child of node.children) visit(child);
  }
  visit(snapshot);
  const extent = (ranges) => {
    let total = 0;
    const groups = /* @__PURE__ */ new Map();
    for (const run of ranges) {
      if ((total += run.count) > 131072 || ranges.length > 4096) throw TypeError("Owned inverse selection resource limit");
      const key2 = run.type.client + ":" + run.type.clock + "/" + run.item.client, list = groups.get(key2) || [];
      list.push([run.item.clock, run.item.clock + run.count]);
      groups.set(key2, list);
    }
    return [...groups].sort(([a], [b]) => a.localeCompare(b)).map(([key2, list]) => {
      list.sort((a, b) => a[0] - b[0]);
      const merged = [];
      for (const [a, b] of list) {
        const last = merged.at(-1);
        if (last && a < last[1]) throw TypeError("Duplicate restored destination");
        if (last && a === last[1]) last[1] = b;
        else merged.push([a, b]);
      }
      return [key2, merged];
    });
  };
  if (!same(extent(fresh), extent(copies.flatMap((copy) => copy.destination.runs)))) throw TypeError("Unaccounted maintained inverse text allocation");
  return { fresh_items: { runs: fresh }, text_items: { runs: [] }, proven_copies: copies };
}
var ownedObservations = /* @__PURE__ */ new WeakMap();
function captureOwnedHistoryObservation(doc) {
  if (!(doc instanceof Y3.Doc) || doc.gc !== false || doc.store.pendingStructs || doc.store.pendingDs) throw TypeError("Unavailable retained owned history observer");
  captureContentEditSnapshot(doc.getXmlFragment("default"));
  const token = Object.freeze({});
  ownedObservations.set(token, { doc, before: Y3.decodeStateVector(Y3.encodeStateVector(doc)), links: redoneLinks(doc) });
  return token;
}
function finishOwnedHistoryObservation(doc, observation) {
  const before = ownedObservations.get(observation);
  if (!before || before.doc !== doc) throw TypeError("Unavailable same-owner history observation");
  const copies = restoredCopies(doc, before.before, before.links), accounting = ownedTextAccounting(doc, before.before, copies);
  ownedObservations.delete(observation);
  return accounting;
}
function replayOwnedHistory(evidence) {
  fields2(evidence, ["sender_state_base64", "current_state_base64", "writer_client", "operation", "footprint", "initial_state_base64", "receipts"]);
  validateOwnedHistory(evidence.operation.history);
  if (!Array.isArray(evidence.receipts) || evidence.receipts.length < 1 || evidence.receipts.length > 4096) throw TypeError("Unavailable bounded accepted history");
  const doc = owner(bytes(evidence.initial_state_base64)), origin = {}, manager = new Y3.UndoManager([doc.getXmlFragment("default"), doc.getMap("relaymark")], { trackedOrigins: /* @__PURE__ */ new Set([origin]), captureTimeout: Infinity });
  protectOwnedHistoryBranches(manager);
  bindOwnedHistoryOwner(manager, evidence.operation.history.owner_id);
  let activeID = null, popped = null, lastRestored = [];
  const event = (e) => {
    if (!manager.undoing && !manager.redoing && activeID) bindOwnedCommandGroup(manager, e, activeID);
  };
  manager.on("stack-item-added", event);
  manager.on("stack-item-updated", event);
  manager.on("stack-item-popped", (e) => {
    popped = e.stackItem;
    bindOwnedCommandHistory(manager, e);
  });
  const inverse = (operation, writer) => {
    validateOwnedHistory(operation.history);
    const stack = operation.history.kind === "undo" ? manager.undoStack : manager.redoStack, group = stack.at(-1)?.meta.get("relaymark:operation_ids");
    if (operation.history.owner_id !== evidence.operation.history.owner_id || !group || !same(group, { owner_id: operation.history.owner_id, reference: operation.history.reference, operation_ids: operation.history.operation_ids })) throw TypeError("Owned history differs from actual accepted group");
    const prior = Y3.decodeStateVector(Y3.encodeStateVector(doc)), links = redoneLinks(doc), initialized = initProseMirrorDoc(doc.getXmlFragment("default"), schema4), expected = applyContentEdit(initialized.doc.toJSON(), operation), updates = [], capture = (u) => updates.push(u);
    doc.clientID = writer ?? 0;
    popped = null;
    doc.on("update", capture);
    try {
      if (operation.history.kind === "undo") manager.undo();
      else manager.redo();
    } finally {
      doc.off("update", capture);
    }
    if (!popped || updates.length !== 1 || !same(initProseMirrorDoc(doc.getXmlFragment("default"), schema4).doc.toJSON(), expected.document)) throw TypeError("Actual maintained inverse disagrees with supplied steps");
    lastRestored = restoredCopies(doc, prior, links);
    return updates[0];
  };
  try {
    let total = bytes(evidence.initial_state_base64).length;
    const seen = /* @__PURE__ */ new Set();
    for (const receipt of evidence.receipts) {
      fields2(receipt, ["transaction_id", "operation", "update_base64", "sender_state_base64"]);
      if (seen.has(receipt.transaction_id)) throw TypeError("Duplicate accepted command receipt");
      seen.add(receipt.transaction_id);
      const sender2 = bytes(receipt.sender_state_base64), update = bytes(receipt.update_base64);
      const receiptOwner = receipt.operation.history ? validateOwnedHistory(receipt.operation.history).owner_id : validateOwnedCommandGroup(receipt.operation.group).owner_id;
      if (receiptOwner !== evidence.operation.history.owner_id) throw TypeError("Mixed maintained history owner receipts");
      total += sender2.length + update.length;
      if (total > 32 * 1024 * 1024) throw TypeError("Oversized accepted history replay");
      Y3.applyUpdate(doc, sender2);
      if (doc.store.pendingStructs || doc.store.pendingDs) throw TypeError("Unsettled accepted sender frontier");
      const beforeBytes = Y3.encodeStateAsUpdate(doc), candidate = owner(beforeBytes);
      try {
        Y3.applyUpdate(candidate, update);
        const footprint = captureContentEditFootprint(candidate, update), writer = observedWriter(footprint, doc);
        if (receipt.operation.history) {
          const actual = inverse(receipt.operation, writer), locked = owner(beforeBytes);
          try {
            compareUpdate(locked, footprint, actual);
          } finally {
            locked.destroy();
          }
        } else {
          const group = validateOwnedCommandGroup(receipt.operation.group);
          if (group.operation_ids.at(-1) !== receipt.transaction_id) throw TypeError("Accepted group does not end in command receipt");
          replayContentEditMutation({ sender_state_base64: receipt.sender_state_base64, current_state_base64: toBase64(beforeBytes), writer_client: writer, operation: receipt.operation, footprint });
          if (group.reference === receipt.transaction_id) manager.stopCapturing();
          activeID = receipt.transaction_id;
          try {
            Y3.applyUpdate(doc, update, origin);
          } finally {
            activeID = null;
          }
          const actualGroup = readOwnedCommandGroup(manager, receipt.transaction_id);
          if (!same(actualGroup, group)) throw TypeError("Accepted prefix differs from maintained group");
        }
      } finally {
        candidate.destroy();
      }
    }
    Y3.applyUpdate(doc, bytes(evidence.sender_state_base64));
    const candidateFrontier = Y3.decodeStateVector(Y3.encodeStateVector(doc)), sender = owner(bytes(evidence.sender_state_base64));
    try {
      if (!same([...candidateFrontier].sort((a, b) => a[0] - b[0]), [...Y3.decodeStateVector(Y3.encodeStateVector(sender))].sort((a, b) => a[0] - b[0])) || !same(captureContentEditSnapshot(doc.getXmlFragment("default")), captureContentEditSnapshot(sender.getXmlFragment("default"))) || !same(intervals(captureContentEditFootprint(doc, Y3.encodeStateAsUpdate(doc)).declared_deletes), intervals(captureContentEditFootprint(sender, Y3.encodeStateAsUpdate(sender)).declared_deletes)) || !same(doc.share.has("relaymark") ? doc.getMap("relaymark").toJSON() : {}, sender.share.has("relaymark") ? sender.getMap("relaymark").toJSON() : {})) throw TypeError("Accepted history does not reconstruct exact sender frontier");
    } finally {
      sender.destroy();
    }
    const current = owner(bytes(evidence.current_state_base64));
    try {
      if (observedWriter(evidence.footprint, current) !== evidence.writer_client) throw TypeError("History writer is not independently observed");
      const frontier = Y3.decodeStateVector(Y3.encodeStateVector(current)), update = inverse(evidence.operation, evidence.writer_client), proof = compareUpdate(current, evidence.footprint, update), accounting = ownedTextAccounting(current, frontier, lastRestored);
      return { ...proof, ...accounting, expected_update_base64: toBase64(update), complete_mutation_correspondence: true, owned_history_correspondence: true, restored_copies: lastRestored };
    } finally {
      current.destroy();
    }
  } finally {
    manager.destroy();
    doc.destroy();
  }
}
export {
  captureOwnedHistoryObservation,
  finishOwnedHistoryObservation,
  replayContentEditMutation
};
