# Magento RequireJS Mixin Examples

Practical Magento 2 mixin examples based on real-world use cases.

---

## Example 1: Extending a UIComponent

**Scenario**: Capture Google Maps coordinates in checkout

**Original Component**: `Vendor_Theme/js/view/checkout/address-autocomplete.js`
```javascript
define([
    'ko',
    'jquery',
    'uiComponent',
    // ...
], function (ko, $, Component, ...) {
    'use strict';

    return Component.extend({
        onAutoCompleteChange: function(place) {
            // Original logic
            this.place = place;
            this.changeFormFields(fieldsValues);
        }
    });
});
```

**Mixin**: `app/code/Vendor/Module/view/frontend/web/js/mixin/address-autocomplete-mixin.js`
```javascript
define([
    'Magento_Checkout/js/model/quote'
], function (quote) {
    'use strict';

    return function (Component) {
        return Component.extend({
            /**
             * Extend onAutoCompleteChange to capture coordinates
             */
            onAutoCompleteChange: function (place) {
                // Call parent method FIRST
                this._super(place);

                // Add custom logic AFTER parent
                if (place && place.geometry && place.geometry.location) {
                    var latitude = place.geometry.location.lat();
                    var longitude = place.geometry.location.lng();

                    var shippingAddress = quote.shippingAddress();
                    if (shippingAddress) {
                        shippingAddress.customAttributes = shippingAddress.customAttributes || {};
                        shippingAddress.customAttributes.latitude = latitude;
                        shippingAddress.customAttributes.longitude = longitude;

                        quote.shippingAddress(shippingAddress);
                        console.log('Coordinates captured:', latitude, longitude);
                    }
                }
            }
        });
    };
});
```

**requirejs-config.js**:
```javascript
var config = {
    config: {
        mixins: {
            'Vendor_Theme/js/view/checkout/address-autocomplete': {
                'Vendor_Module/js/mixin/address-autocomplete-mixin': true
            }
        }
    }
};
```

---

## Example 2: Wrapping a Simple Function

**Scenario**: Add extra validation before performing an action

**Original Function**: `Magento_Checkout/js/action/place-order.js`
```javascript
define([
    'mage/storage',
    'Magento_Checkout/js/model/quote',
    // ...
], function (storage, quote, ...) {
    'use strict';

    return function (paymentData, messageContainer) {
        // Place order logic
        return storage.post(url, JSON.stringify(data));
    };
});
```

**Mixin**: `app/code/Vendor/Module/view/frontend/web/js/mixin/place-order-mixin.js`
```javascript
define([
    'jquery',
    'mage/utils/wrapper'
], function ($, wrapper) {
    'use strict';

    return function (placeOrderAction) {
        return wrapper.wrap(placeOrderAction, function (originalAction, paymentData, messageContainer) {
            console.log('Before place order');

            // Add custom validation
            if (!paymentData.additional_data) {
                paymentData.additional_data = {};
            }
            paymentData.additional_data.custom_field = 'custom_value';

            // Call original action
            var result = originalAction(paymentData, messageContainer);

            // Handle result
            result.done(function(response) {
                console.log('Order placed successfully', response);
            });

            return result;
        });
    };
});
```

**requirejs-config.js**:
```javascript
var config = {
    config: {
        mixins: {
            'Magento_Checkout/js/action/place-order': {
                'Vendor_Module/js/mixin/place-order-mixin': true
            }
        }
    }
};
```

---

## Example 3: Extending Payload Extender

**Scenario**: Add custom data to shipping payload

**Original**: `Magento_Checkout/js/model/shipping-save-processor/payload-extender.js`
```javascript
define([], function () {
    'use strict';

    return function (payload) {
        payload.addressInformation['extension_attributes'] = {};
        return payload;
    };
});
```

**Mixin**: `app/code/Vendor/Module/view/frontend/web/js/mixin/payload-extender-mixin.js`
```javascript
define([
    'Magento_Checkout/js/model/quote'
], function (quote) {
    'use strict';

    return function (payloadExtender) {
        return function (payload) {
            // Call original extender
            payload = payloadExtender(payload);

            // Add custom data
            var shippingAddress = quote.shippingAddress();
            if (shippingAddress && shippingAddress.customAttributes) {
                // Add to shipping address extension attributes
                payload.addressInformation.shipping_address.extension_attributes =
                    payload.addressInformation.shipping_address.extension_attributes || {};

                if (shippingAddress.customAttributes.custom_field) {
                    payload.addressInformation.shipping_address.extension_attributes.custom_field =
                        shippingAddress.customAttributes.custom_field;
                }
            }

            console.log('Extended payload:', payload);
            return payload;
        };
    };
});
```

**requirejs-config.js**:
```javascript
var config = {
    config: {
        mixins: {
            'Magento_Checkout/js/model/shipping-save-processor/payload-extender': {
                'Vendor_Module/js/mixin/payload-extender-mixin': true
            }
        }
    }
};
```

---

## Example 4: Extending Observable in UIComponent

**Scenario**: Add computed observable to a component

**Mixin**:
```javascript
define([
    'ko'
], function (ko) {
    'use strict';

    return function (Component) {
        return Component.extend({
            defaults: {
                customField: ''
            },

            /**
             * Initialize component
             */
            initialize: function () {
                this._super();

                // Add computed observable
                this.computedValue = ko.computed(function () {
                    return this.customField() ? this.customField().toUpperCase() : '';
                }, this);

                return this;
            },

            /**
             * Observe changes
             */
            initObservable: function () {
                this._super()
                    .observe(['customField']);

                return this;
            }
        });
    };
});
```

---

## Example 5: Multiple Method Override

**Scenario**: Override multiple methods in a component

**Mixin**:
```javascript
define([
    'Magento_Checkout/js/model/quote'
], function (quote) {
    'use strict';

    return function (Component) {
        return Component.extend({
            /**
             * Override initialize
             */
            initialize: function () {
                this._super();
                console.log('Component initialized');
                this.setupCustomLogic();
                return this;
            },

            /**
             * Override existing method
             */
            validateShippingInformation: function () {
                var result = this._super();

                // Add extra validation
                if (!this.customValidation()) {
                    return false;
                }

                return result;
            },

            /**
             * Add new method
             */
            customValidation: function () {
                // Custom validation logic
                return true;
            },

            /**
             * Add new method
             */
            setupCustomLogic: function () {
                // Setup custom logic
                console.log('Custom logic setup');
            }
        });
    };
});
```

---

## Example 6: Conditional Logic in Mixin

**Scenario**: Apply logic only under certain conditions

**Mixin**:
```javascript
define([
    'Magento_Checkout/js/model/quote',
    'Magento_Customer/js/model/customer'
], function (quote, customer) {
    'use strict';

    return function (Component) {
        return Component.extend({
            onShippingMethodSelected: function (shippingMethod) {
                // Call parent
                this._super(shippingMethod);

                // Apply custom logic only for logged-in customers
                if (customer.isLoggedIn()) {
                    this.applyCustomerSpecificLogic(shippingMethod);
                }

                // Apply logic only for specific shipping methods
                if (shippingMethod.carrier_code === 'custom_carrier') {
                    this.applyCarrierSpecificLogic(shippingMethod);
                }
            },

            applyCustomerSpecificLogic: function (shippingMethod) {
                console.log('Customer-specific logic', shippingMethod);
            },

            applyCarrierSpecificLogic: function (shippingMethod) {
                console.log('Carrier-specific logic', shippingMethod);
            }
        });
    };
});
```

---

## Example 7: Working with KnockoutJS Observables

**Scenario**: Subscribe to changes in observables

**Mixin**:
```javascript
define([
    'ko'
], function (ko) {
    'use strict';

    return function (Component) {
        return Component.extend({
            initialize: function () {
                this._super();

                // Subscribe to changes in an observable
                if (this.selectedPaymentMethod) {
                    this.selectedPaymentMethod.subscribe(function (newValue) {
                        console.log('Payment method changed:', newValue);
                        this.onPaymentMethodChange(newValue);
                    }, this);
                }

                return this;
            },

            onPaymentMethodChange: function (paymentMethod) {
                // Handle payment method change
                if (paymentMethod === 'custom_payment') {
                    this.showCustomFields(true);
                } else {
                    this.showCustomFields(false);
                }
            }
        });
    };
});
```

---

## Example 8: Storage Module Pattern

**Scenario**: Persist data between components when Magento observables are difficult to manage

**Problem**: The `shippingAddress` observable can be reset or modified by other components, losing custom data.

**Solution**: Create an independent storage module.

### Storage Module: `app/code/Vendor/Module/view/frontend/web/js/model/data-storage.js`

```javascript
define([
    'ko'
], function (ko) {
    'use strict';

    var latitude = ko.observable(null);
    var longitude = ko.observable(null);

    return {
        /**
         * Get latitude
         * @returns {String|null}
         */
        getLatitude: function () {
            return latitude();
        },

        /**
         * Set latitude
         * @param {String} value
         */
        setLatitude: function (value) {
            latitude(value);
        },

        /**
         * Get longitude
         * @returns {String|null}
         */
        getLongitude: function () {
            return longitude();
        },

        /**
         * Set longitude
         * @param {String} value
         */
        setLongitude: function (value) {
            longitude(value);
        },

        /**
         * Check if coordinates are set
         * @returns {Boolean}
         */
        hasCoordinates: function () {
            return latitude() !== null && longitude() !== null;
        },

        /**
         * Clear coordinates
         */
        clear: function () {
            latitude(null);
            longitude(null);
        }
    };
});
```

### Mixin that saves to storage: `capture-mixin.js`

```javascript
define([
    'Vendor_Module/js/model/data-storage'
], function (dataStorage) {
    'use strict';

    return function (Component) {
        return Component.extend({
            onDataCapture: function (data) {
                this._super(data);

                // Store in our custom storage
                if (data.latitude && data.longitude) {
                    dataStorage.setLatitude(String(data.latitude));
                    dataStorage.setLongitude(String(data.longitude));

                    console.log('Data stored:', data);
                }
            }
        });
    };
});
```

### Mixin that reads from storage: `payload-mixin.js`

```javascript
define([
    'Vendor_Module/js/model/data-storage'
], function (dataStorage) {
    'use strict';

    return function (payloadExtender) {
        return function (payload) {
            payload = payloadExtender(payload);

            // Get data from storage
            if (dataStorage.hasCoordinates()) {
                payload.addressInformation.shipping_address.extension_attributes =
                    payload.addressInformation.shipping_address.extension_attributes || {};

                payload.addressInformation.shipping_address.extension_attributes.latitude =
                    dataStorage.getLatitude();
                payload.addressInformation.shipping_address.extension_attributes.longitude =
                    dataStorage.getLongitude();

                console.log('Payload extended from storage');
            }

            return payload;
        };
    };
});
```

### Storage Pattern Advantages:

1. **Guaranteed persistence**: Data is not lost if other components modify the observable
2. **Decoupling**: Components don't need to know the complete observable structure
3. **Simplicity**: Avoids the complexity of synchronizing with Magento observables
4. **Singleton**: A single source of truth for data
5. **Easy to debug**: Simple console logs to verify state

### When to use Storage Pattern:

- ✅ When you need to persist data between multiple checkout steps
- ✅ When the main observable (`quote`, `shippingAddress`, etc.) is frequently reset
- ✅ When multiple components need to access the same data
- ✅ When the observable structure is complex (customAttributes as array, etc.)
- ✅ When you need data available at any point in the flow

### When NOT to use Storage Pattern:

- ❌ For data that already has a logical place in Magento's model
- ❌ For data only used in one component
- ❌ When the observable works correctly without issues

---

## Testing Mixins

### Console Debugging
```javascript
// In your mixin, add console logs
console.log('Mixin loaded');
console.log('Original method called', arguments);
console.log('Data modified:', payload);
```

### Browser DevTools
1. Open Network tab
2. Filter by "js"
3. Look for your mixin file
4. Check if it loads (200 status)
5. Check Console for errors

### RequireJS Debug
```javascript
// In browser console
require.config({ waitSeconds: 0 });
require(['Vendor_Module/js/mixin/custom-mixin'], function(mixin) {
    console.log('Mixin:', mixin);
});
```

---

## Common Patterns Summary

| Component Type | Pattern | Key Method | Use Case |
|---------------|---------|------------|----------|
| UIComponent | `Component.extend({})` | `this._super()` | Extend UI components |
| Simple Function | `wrapper.wrap()` | `originalFunction()` | Wrap action functions |
| Object/Module | Direct wrap | `targetObject()` | Extend modules |
| Payload Extender | Function wrap | Return extended payload | Modify API payloads |
| Observable | `ko.computed()` | Subscribe/observe | React to changes |
| **Storage Module** | **Singleton with `ko.observable`** | **`getData()`/`setData()`** | **Persist data across components** |

---

## Troubleshooting

### Mixin not loading?
1. Check requirejs-config.js syntax
2. Verify file path is correct
3. Clear static content and cache
4. Check browser Network tab

### Method not being called?
1. Verify method name matches exactly
2. Check if parent method exists
3. Ensure correct pattern (extend vs wrap)
4. Add console.log to verify execution

### Changes not visible?
1. Hard refresh browser (Ctrl+Shift+R)
2. Clear browser cache
3. Redeploy static content
4. Check if multiple mixins conflict

---

Remember: Always test your mixins in both development and production modes!