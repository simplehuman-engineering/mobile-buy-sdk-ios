//
//  PaySessionTests.swift
//  PayTests
//
//  Created by Shopify.
//  Copyright (c) 2017 Shopify Inc. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#if canImport(PassKit)

import XCTest
import PassKit
@testable import Pay

class PaySessionTests: XCTestCase {
    
    private let shopName = "Jaded Labs"
    
    // ----------------------------------
    //  MARK: - Init -
    //
    func testInit() {
        let checkout = Models.createCheckout()
        let currency = Models.createCurrency()
        let session  = PaySession(shopName: shopName, checkout: checkout, currency: currency, merchantID: "some-id")
        
        XCTAssertEqual(session.merchantID, "some-id")
        XCTAssertEqual(session.currency.countryCode, currency.countryCode)
        
        XCTAssertFalse(session.identifier.isEmpty)
    }
    
    func testDeprecatedInit() {
        let checkout = Models.createCheckout()
        let currency = Models.createCurrency()
        let session  = PaySession(checkout: checkout, currency: currency, merchantID: "some-id")
        
        XCTAssertEqual(session.shopName, "TOTAL")
    }
    
    func testUniqueIdentifier() {
        let checkout = Models.createCheckout()
        let currency = Models.createCurrency()
        
        let session1 = Models.createSession(checkout: checkout, currency: currency)
        let session2 = Models.createSession(checkout: checkout, currency: currency)
        let session3 = Models.createSession(checkout: checkout, currency: currency)
        
        XCTAssertNotEqual(session1.identifier, session2.identifier)
        XCTAssertNotEqual(session2.identifier, session3.identifier)
    }
    
    // ----------------------------------
    //  MARK: - Payment Request -
    //
    func testPaymentRequest() {
        let checkout = Models.createCheckout()
        let currency = Models.createCurrency()
        let session  = Models.createSession(checkout: checkout, currency: currency)
        
        let digitalCheckout = Models.createCheckout(requiresShipping: false)
        let digitalRequest  = session.paymentRequestUsing(digitalCheckout, currency: currency, merchantID: session.merchantID)
        
        XCTAssertEqual(digitalRequest.countryCode,                   currency.countryCode)
        XCTAssertEqual(digitalRequest.currencyCode,                  currency.currencyCode)
        XCTAssertEqual(digitalRequest.merchantIdentifier,            session.merchantID)
        XCTAssertEqual(digitalRequest.requiredBillingContactFields,  Set([PKContactField.emailAddress, .name, .phoneNumber, .postalAddress]))
        XCTAssertEqual(digitalRequest.requiredShippingContactFields, Set([PKContactField.emailAddress, .name, .phoneNumber, .postalAddress]))
        XCTAssertEqual(digitalRequest.supportedNetworks,             [.visa, .masterCard, .amex])
        XCTAssertEqual(digitalRequest.merchantCapabilities,          [.capability3DS])
        XCTAssertFalse(digitalRequest.paymentSummaryItems.isEmpty)
        
        let shippingCheckout = Models.createCheckout(requiresShipping: true)
        let shippingRequest  = session.paymentRequestUsing(shippingCheckout, currency: currency, merchantID: session.merchantID)
        
        XCTAssertEqual(shippingRequest.requiredShippingContactFields, Set([PKContactField.emailAddress, .name, .phoneNumber, .postalAddress]))
    }
    
    // ----------------------------------
    //  MARK: - Payment Authorization -
    //
    func testPaymentAuthorization() {
        
        let contact      = Models.createContact()
        let shippingRate = Models.createShippingRate()
        
        let payMethod = MockPaymentMethod(displayName: "John's Mastercard", network: .masterCard, type: .credit)
        let token     = MockPaymentToken(paymentMethod: payMethod)
        let payment   = MockPayment(token: token, billingContact: contact, shippingContact: contact, shippingMethod: shippingRate.summaryItem)
        
        let checkout  = Models.createCheckout(requiresShipping: true)
        let delegate  = self.setupDelegateForMockSessionWith(checkout) { session in
            session.shippingRates = [
                shippingRate
            ]
        }
        
        /* -------------------
         ** Success invocation
         */
        delegate.didAuthorizePayment = { session, authorization, checkout, complete in
            
            let tokenString = String(data: token.paymentData, encoding: .utf8)
            XCTAssertEqual(authorization.token, tokenString)
            XCTAssertEqual(authorization.billingAddress.city,  contact.postalAddress!.city)
            XCTAssertEqual(authorization.shippingAddress.city, contact.postalAddress!.city)
            
            XCTAssertNotNil(authorization.shippingRate)
            XCTAssertEqual(authorization.shippingRate!.handle, shippingRate.handle)
            
            complete(.success)
        }
        
        let expectationSuccess = self.expectation(description: "")
        
        MockAuthorizationController.invokeDidAuthorizePaymentHandler(payment) { result in
            XCTAssertEqual(result.status, .success)
            expectationSuccess.fulfill()
        }
        
        self.wait(for: [expectationSuccess], timeout: 10.0)
        
        /* -------------------
         ** Failure invocation
         */
        delegate.didAuthorizePayment = { session, authorization, checkout, complete in
            complete(.failure(errors: [
                NSError(domain: "", code: 0, userInfo: [:])
            ]))
        }
        
        let expectationFailure = self.expectation(description: "")
        
        MockAuthorizationController.invokeDidAuthorizePaymentHandler(payment) { result in
            XCTAssertEqual(result.status, .failure)
            XCTAssertNotEqual(result.errors.count, 0)
            expectationFailure.fulfill()
        }
        
        self.wait(for: [expectationFailure], timeout: 10.0)
    }
    
    // ----------------------------------
    //  MARK: - Select Shipping Contact -
    //
    func testSelectShippingContactWithInvalidAddress() {
        
        let checkout = Models.createCheckout(requiresShipping: true)
        let delegate = self.setupDelegateForMockSessionWith(checkout)
        
        delegate.didRequestShippingRates = { session, postalAddress, checkout, provide in
            XCTFail()
        }
        
        let expectation = self.expectation(description: "")
        
        MockAuthorizationController.invokeDidSelectShippingContactHandler(PKContact()) { result in
            XCTAssertEqual(result.status, .failure)
            XCTAssertEqual(result.shippingMethods, [])
            XCTAssertEqual(result.paymentSummaryItems, checkout.summaryItems(for: self.shopName))
            expectation.fulfill()
        }
        
        self.wait(for: [expectation], timeout: 10.0)
    }
    
    func testSelectShippingContactWithEmptyRates() {
        
        let checkout = Models.createCheckout(requiresShipping: true)
        let delegate = self.setupDelegateForMockSessionWith(checkout)
        
        let shippingContact    = Models.createContact()
        let invalidExpectation = self.expectation(description: "")
        
        delegate.didRequestShippingRates = { session, postalAddress, checkout, provide in
            invalidExpectation.fulfill()
            provide(checkout, [], [
                PKPaymentRequest.paymentShippingAddressInvalidError(withKey: CNContactPostalAddressesKey, localizedDescription: "Invalid shipping address")
            ])
        }
        
        let expectation = self.expectation(description: "")
        
        MockAuthorizationController.invokeDidSelectShippingContactHandler(shippingContact) { result in
            XCTAssertEqual(result.status, .failure)
            XCTAssertEqual(result.shippingMethods, [])
            XCTAssertEqual(result.paymentSummaryItems, checkout.summaryItems(for: self.shopName))
            
            expectation.fulfill()
        }
        
        self.wait(for: [invalidExpectation, expectation], timeout: 0)
    }
    
    func testSelectShippingContact() {
        
        let checkout = Models.createCheckout(requiresShipping: true)
        let delegate = self.setupDelegateForMockSessionWith(checkout)
        
        let shippingContact  = Models.createContact()
        let shippingAddress  = Models.createAddress()
        let shippingRate     = Models.createShippingRate()
        let addressCheckout  = Models.createCheckout(shippingAddress: shippingAddress)
        let shippingCheckout = Models.createCheckout(shippingRate: shippingRate)
        
        let e1 = self.expectation(description: "")
        delegate.didRequestShippingRates = { session, postalAddress, checkout, provide in
            e1.fulfill()
            
            XCTAssertNil(checkout.shippingAddress)
            XCTAssertNil(checkout.shippingRate)
            
            provide(addressCheckout, [shippingRate], nil)
        }
        
        let e2 = self.expectation(description: "")
        delegate.didSelectShippingRate = { session, shippingRate, checkout, provide in
            e2.fulfill()
            
            XCTAssertNotNil(checkout.shippingAddress)
            XCTAssertNil(checkout.shippingRate)
            
            provide(shippingCheckout, nil)
        }
        
        let expectation = self.expectation(description: "")
        
        MockAuthorizationController.invokeDidSelectShippingContactHandler(shippingContact) { result in
            
            XCTAssertEqual(result.status, .success)
            XCTAssertEqual(result.shippingMethods.count, 1)
            XCTAssertEqual(result.paymentSummaryItems, shippingCheckout.summaryItems(for: self.shopName))
            
            expectation.fulfill()
        }
        
        self.wait(for: [e1, e2, expectation], timeout: 0)
    }
    
    func testSelectShippingContactWithoutShippingSuccess() {
        
        let checkout = Models.createCheckout(requiresShipping: false)
        let delegate = self.setupDelegateForMockSessionWith(checkout)
        
        let shippingContact  = Models.createContact()
        let shippingAddress  = Models.createAddress()
        let addressCheckout  = Models.createCheckout(requiresShipping: false, shippingAddress: shippingAddress)
        
        let e1 = self.expectation(description: "")
        delegate.didUpdateShippingAddress = { session, postalAddress, checkout, provide in
            e1.fulfill()
            
            XCTAssertNil(checkout.shippingAddress)
            
            provide(addressCheckout, nil)
        }
        
        let expectation = self.expectation(description: "")
        
        MockAuthorizationController.invokeDidSelectShippingContactHandler(shippingContact) { result in
            
            XCTAssertEqual(result.status, .success)
            XCTAssertEqual(result.shippingMethods.count, 0)
            XCTAssertEqual(result.paymentSummaryItems, checkout.summaryItems(for: self.shopName))
            
            expectation.fulfill()
        }
        
        self.wait(for: [e1, expectation], timeout: 0)
    }
    
    func testSelectShippingContactWithoutShippingFailure() {
        
        let checkout = Models.createCheckout(requiresShipping: false)
        let delegate = self.setupDelegateForMockSessionWith(checkout)
        
        let shippingContact  = Models.createContact()
        
        let e1 = self.expectation(description: "")
        delegate.didUpdateShippingAddress = { session, postalAddress, checkout, provide in
            e1.fulfill()
            
            XCTAssertNil(checkout.shippingAddress)
            
            provide(nil, [
                NSError(domain: "", code: 0, userInfo: [:])
            ])
        }
        
        let expectation = self.expectation(description: "")
        
        MockAuthorizationController.invokeDidSelectShippingContactHandler(shippingContact) { result in
            
            XCTAssertEqual(result.status, .failure)
            XCTAssertTrue(result.shippingMethods.isEmpty)
            XCTAssertTrue(result.paymentSummaryItems.isEmpty)
            
            expectation.fulfill()
        }
        
        self.wait(for: [e1, expectation], timeout: 0)
    }
    
    func testSelectShippingContactFailure() {
        
        let checkout = Models.createCheckout(requiresShipping: true)
        let delegate = self.setupDelegateForMockSessionWith(checkout)
        
        let shippingContact  = Models.createContact()
        let shippingAddress  = Models.createAddress()
        let shippingRate     = Models.createShippingRate()
        let addressCheckout  = Models.createCheckout(shippingAddress: shippingAddress)
        
        let e1 = self.expectation(description: "")
        delegate.didRequestShippingRates = { session, postalAddress, checkout, provide in
            e1.fulfill()
            provide(addressCheckout, [shippingRate], nil)
        }
        
        let e2 = self.expectation(description: "")
        delegate.didSelectShippingRate = { session, shippingRate, checkout, provide in
            e2.fulfill()
            
            XCTAssertNotNil(checkout.shippingAddress)
            XCTAssertNil(checkout.shippingRate)
            
            provide(nil, [
                NSError(domain: "", code: 0, userInfo: [:])
            ])
        }
        
        let expectation = self.expectation(description: "")
        
        MockAuthorizationController.invokeDidSelectShippingContactHandler(shippingContact) { result in
            
            XCTAssertEqual(result.status, .failure)
            XCTAssertTrue(result.shippingMethods.isEmpty)
            XCTAssertTrue(result.paymentSummaryItems.isEmpty)
            
            expectation.fulfill()
        }
        
        self.wait(for: [e1, e2, expectation], timeout: 0)
    }
    
    // ----------------------------------
    //  MARK: - Select Shipping Method -
    //
    func testSelectShippingMethodWithoutShippingRates() {
        
        let checkout = Models.createCheckout(requiresShipping: true)
        let delegate = self.setupDelegateForMockSessionWith(checkout)
        
        delegate.didSelectShippingRate = { session, shippingRate, checkout, provide in
            XCTFail()
        }
        
        let shippingRate   = Models.createShippingRate()
        let shippingMethod = shippingRate.summaryItem
        
        let expectation = self.expectation(description: "")
        
        MockAuthorizationController.invokeDidSelectShippingMethodHandler(shippingMethod) { result in
            XCTAssertEqual(result.status, .failure)
            XCTAssertEqual(result.paymentSummaryItems, checkout.summaryItems(for: self.shopName))
            
            expectation.fulfill()
        }
        
        self.wait(for: [expectation], timeout: 10.0)
    }
    
    func testSelectShippingMethodWithNilCheckout() {

        let shippingRate   = Models.createShippingRate()
        let shippingMethod = shippingRate.summaryItem

        let checkout = Models.createCheckout(requiresShipping: true)
        let delegate = self.setupDelegateForMockSessionWith(checkout) { session in

            session.checkout      = checkout
            session.shippingRates = [
                shippingRate
            ]
        }

        delegate.didSelectShippingRate = { session, selectedShippingRate, checkoutToUpdate, provide in
            provide(nil, [
                NSError(domain: "", code: 0, userInfo: [:])
            ])
        }

        let expectation = self.expectation(description: "")

        MockAuthorizationController.invokeDidSelectShippingMethodHandler(shippingMethod) { result in
            XCTAssertEqual(result.status, .failure)
            XCTAssertTrue(result.paymentSummaryItems.isEmpty)

            expectation.fulfill()
        }

        self.wait(for: [expectation], timeout: 10.0)
    }

    func testSelectShippingMethod() {

        let shippingRate   = Models.createShippingRate()
        let shippingMethod = shippingRate.summaryItem

        let checkout = Models.createCheckout(requiresShipping: true)
        let delegate = self.setupDelegateForMockSessionWith(checkout) { session in

            session.checkout      = checkout
            session.shippingRates = [
                shippingRate
            ]
        }

        let updatedCheckout = Models.createCheckout(
            requiresShipping: true,
            shippingRate:     shippingRate
        )

        delegate.didSelectShippingRate = { session, selectedShippingRate, checkoutToUpdate, provide in
            provide(updatedCheckout, nil)
        }

        XCTAssertNil(checkout.shippingRate)

        let expectation = self.expectation(description: "")

        MockAuthorizationController.invokeDidSelectShippingMethodHandler(shippingMethod) { result in
            XCTAssertEqual(result.status, .success)
            XCTAssertEqual(updatedCheckout.summaryItems(for: self.shopName), result.paymentSummaryItems)

            expectation.fulfill()
        }

        self.wait(for: [expectation], timeout: 10.0)
    }

    // ----------------------------------
    //  MARK: - Payment Authorization -
    //
    func testAuthorizationFinished() {

        let checkout    = Models.createCheckout(requiresShipping: true)
        let delegate    = self.setupDelegateForMockSessionWith(checkout)
        let expectation = self.expectation(description: "")

        delegate.didFinish = { session in
            expectation.fulfill()
        }
        MockAuthorizationController.invokeDidFinish()

        self.wait(for: [expectation], timeout: 10)
    }
    
    func testSessionForwardsShippingContact() {
        let checkout = Models.createCheckout(requiresShipping: true)
        let session  = Models.createSession(checkout: checkout, currency: Models.createCurrency())

        let shippingContact = Models.createContact()
        let shippingMethods = [Models.createShippingMethod()]
        let summaryItems    = checkout.summaryItems(for: self.shopName)

        let e1 = self.expectation(description: "")
        session.didSelectShippingContactHandler = { controller, contact, completion in
            XCTAssertTrue(contact === shippingContact)
            let result = PKPaymentRequestShippingContactUpdate()
            result.status = .success
            result.shippingMethods = shippingMethods
            result.paymentSummaryItems = summaryItems
            completion(result)
            e1.fulfill()
            return .unhandled
        }
        
        session.authorize()

        let e2 = self.expectation(description: "")
        MockAuthorizationController.invokeDidSelectShippingContactHandler(shippingContact) { result in

            XCTAssertEqual(result.status,              .success)
            XCTAssertEqual(result.shippingMethods,     shippingMethods)
            XCTAssertEqual(result.paymentSummaryItems, summaryItems)

            e2.fulfill()
        }

        self.wait(for: [e1, e2], timeout: 2.0)
    }
    
    func testSessionForwardsShippingMethod() {

        let shippingMethod  = Models.createShippingMethod()
        let checkout        = Models.createCheckout(requiresShipping: true, shippingRate: Models.createShippingRate())
        let session         = Models.createSession(checkout: checkout, currency: Models.createCurrency())
        let summaryItems    = checkout.summaryItems(for: self.shopName)

        let e1 = self.expectation(description: "")
        session.didSelectShippingMethodHandler = { controller, method, completion in
            XCTAssertTrue(method === shippingMethod)
            let result = PKPaymentRequestShippingMethodUpdate()
            result.status = .success
            result.paymentSummaryItems = summaryItems
            completion(result)
            e1.fulfill()
            return .handled
        }

        session.authorize()

        let e2 = self.expectation(description: "")
        MockAuthorizationController.invokeDidSelectShippingMethodHandler(shippingMethod) { result in
            XCTAssertEqual(result.status,              .success)
            XCTAssertEqual(result.paymentSummaryItems, summaryItems)
            e2.fulfill()
        }

        self.wait(for: [e1, e2], timeout: 2.0)
    }
    
    func testSessionForwardsAuthorizedPayment() {

        let checkout = Models.createCheckout(requiresShipping: true, shippingRate: Models.createShippingRate())
        let session  = Models.createSession(checkout: checkout, currency: Models.createCurrency())

        let method   = MockPaymentMethod(displayName: "Test Payment", network: .amex, type: .credit)
        let token    = MockPaymentToken(paymentMethod: method)
        let payment  = MockPayment(token: token)

        let e1 = self.expectation(description: "")
        session.didAuthorizePaymentHandler = { controller, currentPayment, completion in
            XCTAssertTrue(currentPayment === payment)
            let result = PKPaymentAuthorizationResult(status: .success, errors: nil)
            completion(result)
            e1.fulfill()
            return .handled
        }

        session.authorize()

        let e2 = self.expectation(description: "")
        MockAuthorizationController.invokeDidAuthorizePaymentHandler(payment) { result in
            XCTAssertEqual(result.status, .success)
            e2.fulfill()
        }

        self.wait(for: [e1, e2], timeout: 2.0)
    }
    
    // ----------------------------------
    //  MARK: - Session Delegate -
    //
    private func setupDelegateForMockSessionWith(_ checkout: PayCheckout, configure: ((PaySession) -> Void)? = nil) -> MockSessionDelegate {
        let currency = Models.createCurrency()
        let session  = Models.createSession(checkout: checkout, currency: currency)
        let delegate = MockSessionDelegate(session: session)
        
        configure?(session)
        
        session.authorize()
        
        return delegate
    }
}

#endif
