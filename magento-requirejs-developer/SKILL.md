---
name: magento-requirejs-developer
description: Expert in JavaScript mixin development and RequireJS extensions for Magento 2. Use when extending UI components, creating mixins, wrapping JavaScript functions, or modifying frontend behavior without changing core files. Masters UIComponent extension patterns, wrapper.wrap() for functions, payload extenders, and knockout observables.
---

# Magento RequireJS & Mixin Developer

**Expert in JavaScript mixin development and RequireJS extensions for Magento 2.** Masters the correct patterns for extending UI components, simple functions, objects, and JavaScript modules following Magento core best practices.

## Expertise

- **RequireJS Configuration**: Configuration of mixins, maps, shim, and paths
- **UIComponent Extension**: Extending UI components using `.extend()` and `this._super()`
- **Function Wrapping**: Correct use of `wrapper.wrap()` for simple functions
- **Payload Extenders**: Extending payloads in checkout and other areas
- **JavaScript Architecture**: Design patterns and Magento 2 frontend architecture
- **Debugging**: Identifying and resolving common mixin issues

## When to Use This Skill

Invoke this skill when:
- You need to extend or modify existing JavaScript behavior in Magento
- You must create mixins for Magento UI components
- You need to intercept JavaScript functions without modifying the original code
- You need to add functionality to checkout (payload extenders, validators, etc.)
- You have problems with mixins that don't execute or work correctly
- You must follow Magento core best practices for JavaScript

## Key Patterns

### 1. UIComponent Extension (`.extend()`)
For components that inherit from `uiComponent`:
```javascript
define([
    'Magento_Checkout/js/model/quote'
], function (quote) {
    'use strict';

    return function (Component) {
        return Component.extend({
            methodName: function (args) {
                // Call parent method
                this._super(args);

                // Your custom logic
                console.log('Extended method');
            }
        });
    };
});
```

### 2. Function Wrapping (`wrapper.wrap()`)
For simple functions that return a function:
```javascript
define([
    'mage/utils/wrapper'
], function (wrapper) {
    'use strict';

    return function (targetFunction) {
        return wrapper.wrap(targetFunction, function (originalFunction, arg1, arg2) {
            // Pre-processing
            console.log('Before original');

            // Call original function
            var result = originalFunction(arg1, arg2);

            // Post-processing
            console.log('After original');

            return result;
        });
    };
});
```

### 3. Object Extension
For modules that return objects `{}`:
```javascript
define([], function () {
    'use strict';

    return function (targetObject) {
        return function (payload) {
            // Call original
            payload = targetObject(payload);

            // Extend payload
            payload.customData = 'value';

            return payload;
        };
    };
});
```

### 4. Storage Module Pattern
For persisting data between components when observables are complex:
```javascript
define([
    'ko'
], function (ko) {
    'use strict';

    var storedData = ko.observable(null);

    return {
        getData: function () {
            return storedData();
        },

        setData: function (value) {
            storedData(value);
        },

        hasData: function () {
            return storedData() !== null;
        },

        clear: function () {
            storedData(null);
        }
    };
});
```

## Workflow

When asked to create or fix a mixin:

1. **Identify Component Type**
   - Use `Read` tool to examine the target component
   - Determine if it's:
     - UIComponent (uses `Component.extend()`)
     - Simple function (returns function)
     - Object with methods (returns `{}`)
     - Action/Model (specific patterns)

2. **Choose Correct Pattern**
   - UIComponent → Use `.extend()` with `this._super()`
   - Simple function → Use `wrapper.wrap()`
   - Object → Direct extension
   - Payload extender → Function wrapping pattern

3. **Create Mixin File**
   - Place in: `{Vendor}/{Module}/view/{area}/web/js/mixin/{name}-mixin.js`
   - Use proper dependencies
   - Follow naming convention: `{original-name}-mixin.js`

4. **Configure RequireJS**
   - Create/update `requirejs-config.js`
   - Add mixin mapping in `config.mixins`
   - Use correct module path

5. **Deploy Static Content**
   - Clean static content: `rm -rf pub/static/frontend/* var/view_preprocessed/*`
   - Deploy: `bin/magento setup:static-content:deploy`
   - Flush cache: `bin/magento cache:flush`

6. **Test & Debug**
   - Check browser console for errors
   - Verify mixin is loaded in Network tab
   - Add console.log for debugging
   - Test the extended functionality

## Common Mistakes to Avoid

### ❌ Wrong Pattern for UIComponent
```javascript
// DON'T do this for UIComponents
return function (targetComponent) {
    targetComponent.methodName = wrapper.wrap(
        targetComponent.methodName,
        function (originalFunction, args) {
            originalFunction.call(this, args);
        }
    );
    return targetComponent;
};
```

### ✅ Correct Pattern for UIComponent
```javascript
// DO this for UIComponents
return function (Component) {
    return Component.extend({
        methodName: function (args) {
            this._super(args);
            // Your code
        }
    });
};
```

### ❌ Wrong: Not Returning All Arguments in beforePlugin
```javascript
// DON'T forget to return all arguments
public function beforeValidateForCart(
    QuoteAddressValidator $subject,
    AddressInterface $address
): array {
    // ... modifications
    return [$address]; // WRONG: Missing $cart parameter
}
```

### ✅ Correct: Return All Arguments
```javascript
// DO return all method arguments
public function beforeValidateForCart(
    QuoteAddressValidator $subject,
    CartInterface $cart,
    AddressInterface $address
): array {
    // ... modifications
    return [$cart, $address]; // CORRECT
}
```

## RequireJS Config Patterns

### Basic Mixin
```javascript
var config = {
    config: {
        mixins: {
            'Magento_Checkout/js/view/payment/default': {
                'Vendor_Module/js/mixin/payment-mixin': true
            }
        }
    }
};
```

### Multiple Mixins
```javascript
var config = {
    config: {
        mixins: {
            'Magento_Checkout/js/model/quote': {
                'Vendor_Module/js/mixin/quote-mixin': true
            },
            'Magento_Checkout/js/action/place-order': {
                'Vendor_Module/js/mixin/place-order-mixin': true
            }
        }
    }
};
```

### Map (Override Entire Module)
```javascript
var config = {
    map: {
        '*': {
            'Magento_Checkout/js/model/shipping-rate-validator/usps':
                'Vendor_Module/js/model/shipping-rate-validator/usps'
        }
    }
};
```

## Debugging Checklist

When a mixin doesn't work:

1. ✅ Check file exists
2. ✅ Verify requirejs-config.js syntax is valid
3. ✅ Confirm mixin path is correct (no typos)
4. ✅ Check static content is deployed
5. ✅ Clear browser cache (Ctrl+Shift+R)
6. ✅ Check browser console for JavaScript errors
7. ✅ Verify original component path is correct
8. ✅ Ensure correct pattern is used (extend vs wrap)
9. ✅ Check Network tab to see if mixin file loads
10. ✅ Add console.log to verify mixin executes

### Common Deploy Issues

**404 Error - File not found:**
```
GET /static/.../Module/js/file.js 404 (Not Found)
```
**Solution**: File wasn't deployed. Check:
- File exists in source: `app/code/Vendor/Module/view/frontend/web/js/file.js`
- Clean and redeploy: `rm -rf pub/static/frontend/* && bin/magento setup:static-content:deploy`
- Verify deployed: Check `pub/static/frontend/{Vendor}/{theme}/{locale}/Module_Name/js/file.js` exists

**MIME Type Error:**
```
Refused to execute script because its MIME type ('text/plain') is not executable
```
**Solution**: File deployed incorrectly or permission issue. Check:
- Verify source file is valid JavaScript
- Check if file was created with restrictive permissions
- Container user must be able to read the file during deploy

**Script Error:**
```
Uncaught Error: Script error for "Module/js/file"
```
**Solution**: RequireJS couldn't load the module. Check:
- Module path is correct in requirejs-config.js
- File was deployed successfully
- No JavaScript syntax errors in the file
- Dependencies are correctly defined

## Examples from Magento Core

### UIComponent Extension
```
vendor/magento/module-checkout/view/frontend/web/js/view/payment/default.js
```

### Function Wrapping
```
vendor/magento/module-checkout-agreements/view/frontend/web/js/model/place-order-mixin.js
```

### Payload Extender
```
vendor/magento/module-checkout/view/frontend/web/js/model/shipping-save-processor/payload-extender.js
```

## Key Magento Frontend Modules

Common modules to extend:

- `Magento_Checkout/js/model/quote` - Quote management
- `Magento_Checkout/js/model/shipping-save-processor/default` - Shipping processor
- `Magento_Checkout/js/model/shipping-save-processor/payload-extender` - Payload extension
- `Magento_Checkout/js/action/place-order` - Place order action
- `Magento_Checkout/js/action/set-payment-information` - Payment info
- `Magento_Checkout/js/view/payment/default` - Payment component
- `Magento_Ui/js/form/element/abstract` - UI form elements
- `uiComponent` - Base UI component

## Best Practices

1. **Always read the original component first** before creating a mixin
2. **Use the correct pattern** based on component type
3. **Keep mixins focused** - one responsibility per mixin
4. **Add descriptive console.logs** during development
5. **Remove console.logs** in production code
6. **Test in both logged-in and guest checkout**
7. **Check for conflicts** with other modules
8. **Document your mixins** with clear comments
9. **Follow Magento coding standards** for JavaScript
10. **Use strict mode**: `'use strict';`

## Related Documentation

- Magento DevDocs: JavaScript Development
- RequireJS Documentation
- Knockout.js Documentation (for UI components)
- Magento UI Components Guide

## Command Reference

```bash
# Clean static content
rm -rf pub/static/frontend/* var/view_preprocessed/* generated/code/*

# Deploy static content
bin/magento setup:static-content:deploy {locale} -f

# Deploy specific theme
bin/magento setup:static-content:deploy {locale} --theme {Vendor}/{theme} -f

# Flush cache
bin/magento cache:flush
```

---

**Remember**: The key to successful Magento JavaScript development is understanding the component type and choosing the correct extension pattern. Always examine the original component before creating your mixin!