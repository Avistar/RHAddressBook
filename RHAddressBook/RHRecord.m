//
//  RHRecord.m
//  RHAddressBook
//
//  Created by Richard Heard on 11/11/11.
//  Copyright (c) 2011 Richard Heard. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions
//  are met:
//  1. Redistributions of source code must retain the above copyright
//  notice, this list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright
//  notice, this list of conditions and the following disclaimer in the
//  documentation and/or other materials provided with the distribution.
//  3. The name of the author may not be used to endorse or promote products
//  derived from this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
//  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
//  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
//  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
//  NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
//  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
//  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "RHRecord.h"
#import "RHRecord_Private.h"

#import "RHAddressBook.h"
#import "RHAddressBook_private.h"
#import "RHMultiValue.h"

@implementation RHRecord

-(id)initWithAddressBook:(RHAddressBook*)addressBook recordRef:(ABRecordRef)recordRef{
    self = [super init];
    if (self) {
        _addressBook = [addressBook retain];
        _recordRef = CFRetain(recordRef);

        //check in so we can be added to the weak link cache
        if (_addressBook){
            [_addressBook _recordCheckIn:self];
        }
    }
    return self;
}
#pragma mark - thread safe action block
-(void)performRecordAction:(void (^)(ABRecordRef recordRef))actionBlock waitUntilDone:(BOOL)wait{
    //if we have an address book perform it on that thread
    if (_addressBook){
        CFRetain(_recordRef);
        [_addressBook performAddressBookAction:^(ABAddressBookRef addressBookRef) {
            actionBlock(_recordRef);
            CFRelease(_recordRef);
        } waitUntilDone:wait];
    } else {
        //otherwise, a user created object... just use current thread.
        actionBlock(_recordRef);
    }

}



#pragma mark - properties

@synthesize addressBook=_addressBook;
@synthesize recordRef=_recordRef;

-(ABRecordID)recordID{
    
    __block ABRecordID recordID = kABPropertyInvalidID;
    
    [self performRecordAction:^(ABRecordRef recordRef) {
        recordID = ABRecordGetRecordID(recordRef);
    } waitUntilDone:YES];
    
    return recordID;
}

-(ABRecordType)recordType{

    __block ABRecordType recordType;
    
    [self performRecordAction:^(ABRecordRef recordRef) {
        recordType = ABRecordGetRecordType(recordRef);
    } waitUntilDone:YES];
    
    return recordType;
}

-(NSString*)compositeName{
   __block NSString *compositeName = nil;

    [self performRecordAction:^(ABRecordRef recordRef) {
        compositeName = (NSString*)ABRecordCopyCompositeName(recordRef);
    } waitUntilDone:YES];

    return [compositeName autorelease];
}


#pragma mark - generic getter/setter/remover
-(id)getBasicValueForPropertyID:(ABPropertyID)propertyID{
    if (!_recordRef) return nil; //no record ref
    if (propertyID == kABPropertyInvalidID) return nil; //invalid    
    
    __block CFTypeRef value = NULL;
    
    [self performRecordAction:^(ABRecordRef recordRef) {
        value = ABRecordCopyValue(recordRef, propertyID);
    } waitUntilDone:YES];

    id result = [(id)value copy];
    if (value) CFRelease(value);
    
    return [result autorelease];
}


-(BOOL)setBasicValue:(CFTypeRef)value forPropertyID:(ABPropertyID)propertyID error:(NSError**)error{
    if (!_recordRef) return false; //no record ref
    if (propertyID == kABPropertyInvalidID) return false; //invalid
    if (value == NULL) return [self unsetBasicValueForPropertyID:propertyID error:error]; //allow NULL to unset the property
    
    __block CFErrorRef cfError = NULL;
    __block BOOL result;
    [self performRecordAction:^(ABRecordRef recordRef) {
        result = ABRecordSetValue(recordRef, propertyID, value, &cfError);
    } waitUntilDone:YES];

    if (error) *error = (NSError*)cfError;
    return result;
}

-(BOOL)unsetBasicValueForPropertyID:(ABPropertyID)propertyID error:(NSError**)error{
    if (!_recordRef) return false; //no record ref
    if (propertyID == kABPropertyInvalidID) return false; //invalid

    __block CFErrorRef cfError = NULL;
    __block BOOL result;
    [self performRecordAction:^(ABRecordRef recordRef) {
        result = ABRecordRemoveValue(recordRef, propertyID, &cfError);
    } waitUntilDone:YES];

    if (error) *error = (NSError*)cfError;
    return result;
}


#pragma mark - generic multi value getter/setter/remover
-(RHMultiValue*)getMultiValueForPropertyID:(ABPropertyID)propertyID{
    if (!_recordRef) return nil; //no record ref
    if (propertyID == kABPropertyInvalidID) return nil; //invalid    
    
    __block ABMultiValueRef valueRef = NULL;
    
    [self performRecordAction:^(ABRecordRef recordRef) {
        valueRef = ABRecordCopyValue(recordRef, propertyID);
    } waitUntilDone:YES];
    
    RHMultiValue *multiValue = nil;
    if (valueRef){
        multiValue = [[RHMultiValue alloc] initWithMultiValueRef:valueRef];
        CFRelease(valueRef);
    }    
    return [multiValue autorelease];
}

-(BOOL)setMultiValue:(RHMultiValue*)multiValue forPropertyID:(ABPropertyID)propertyID error:(NSError**)error{
    if (multiValue == NULL) return [self unsetMultiValueForPropertyID:propertyID error:error]; //allow NULL to unset the property
    return [self setBasicValue:multiValue.multiValueRef forPropertyID:propertyID error:error];
}

-(BOOL)unsetMultiValueForPropertyID:(ABPropertyID)propertyID error:(NSError**)error{
    //this should just be able to be forwarded
   return [self unsetBasicValueForPropertyID:propertyID error:error];
}


#pragma mark - forward
-(BOOL)save{
    return [_addressBook save];
}
-(BOOL)save:(NSError**)error{
    return [_addressBook save:error];
}
-(BOOL)hasUnsavedChanges{
    return [_addressBook hasUnsavedChanges];
}
-(void)revert{
    [_addressBook revert];
}


#pragma mark - cleanup

-(void)dealloc {
    
    //check out so we can be removed from the weak link lookup cache
    if (_addressBook){
        [_addressBook _recordCheckOut:self];
    }
    
    [_addressBook release]; _addressBook = nil;
    if (_recordRef) CFRelease(_recordRef);
    [super dealloc];
}

#pragma mark - misc
-(NSString*)description{
    return [NSString stringWithFormat:@"<%@: %p> name:%@", NSStringFromClass([self class]), self, self.compositeName];
}

+(NSString*)descriptionForRecordType:(ABRecordType)type{
    switch (type) {
        case kABPersonType:    return @"kABPersonType - Person Record Type";
        case kABGroupType:    return @"kABGroupType - Group Record Type";
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 50000
        case kABSourceType:    return @"kABSourceType - Source Record Type";
#endif            
        default: return @"Unknown Property Type";
    }
}

+(NSString*)descriptionForPropertyType:(ABPropertyType)type{
    switch (type) {
        case kABInvalidPropertyType:    return @"kABInvalidPropertyType - Invalid Property Type";
        case kABStringPropertyType:     return @"kABStringPropertyType - String Property Type";
        case kABIntegerPropertyType:    return @"kABIntegerPropertyType - Integer Property Type";
        case kABRealPropertyType:       return @"kABRealPropertyType - Real Property Type";
        case kABDateTimePropertyType:   return @"kABDateTimePropertyType - Date Time Property Type";
        case kABDictionaryPropertyType: return @"kABDictionaryPropertyType - Dictionary Property Type";

        case kABMultiStringPropertyType:     return @"kABMultiStringPropertyType - Multi String Property Type";
        case kABMultiIntegerPropertyType:    return @"kABMultiIntegerPropertyType - Multi Integer Property Type";
        case kABMultiRealPropertyType:       return @"kABMultiRealPropertyType - Multi Real Property Type";
        case kABMultiDateTimePropertyType:   return @"kABMultiDateTimePropertyType - Multi Date Time Property Type";
        case kABMultiDictionaryPropertyType: return @"kABMultiDictionaryPropertyType - Multi Dictionary Property Type";
            
        default: return @"Unknown Property Type";
    }
}


@end