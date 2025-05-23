//
//  Copyright (c) Marcin Krzyżanowski. All rights reserved.
//
//  THIS SOURCE CODE AND ANY ACCOMPANYING DOCUMENTATION ARE PROTECTED BY
//  INTERNATIONAL COPYRIGHT LAW. USAGE IS BOUND TO THE LICENSE AGREEMENT.
//  This notice may not be removed from this file.
//

#import "ObjectivePGPObject.h"
#import "PGPArmor.h"
#import "PGPCompressedPacket.h"
#import "PGPCryptoUtils.h"
#import "PGPKey+Private.h"
#import "PGPKey.h"
#import "PGPLiteralPacket.h"
#import "PGPMPI.h"
#import "PGPS2K.h"
#import "PGPModificationDetectionCodePacket.h"
#import "PGPOnePassSignaturePacket.h"
#import "PGPPacketFactory.h"
#import "PGPPartialKey.h"
#import "PGPPublicKeyEncryptedSessionKeyPacket.h"
#import "PGPSymetricKeyEncryptedSessionKeyPacket.h"
#import "PGPPublicKeyPacket.h"
#import "PGPSecretKeyPacket.h"
#import "PGPSignaturePacket.h"
#import "PGPPartialSubKey.h"
#import "PGPSymmetricallyEncryptedDataPacket.h"
#import "PGPSymmetricallyEncryptedIntegrityProtectedDataPacket.h"
#import "PGPUser.h"
#import "PGPUserIDPacket.h"
#import "NSMutableData+PGPUtils.h"
#import "NSArray+PGPUtils.h"
#import "PGPKeyring.h"
#import "PGPKeyring+Private.h"

#import "PGPFoundation.h"
#import "PGPLogging.h"
#import "PGPMacros+Private.h"
#import "PGPUser+Private.h"
#import "PGPVerification.h"

NS_ASSUME_NONNULL_BEGIN

@implementation ObjectivePGP

- (instancetype)init {
    if ((self = [super init])) {
        //
    }
    return self;
}

+ (ObjectivePGP *)sharedInstance {
    static ObjectivePGP *_ObjectivePGP;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _ObjectivePGP = [[ObjectivePGP alloc] init];
    });
    return _ObjectivePGP;
}

+ (PGPKeyring *)defaultKeyring {
    static PGPKeyring *_keyring;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _keyring = [[PGPKeyring alloc] init];
    });
    return _keyring;
}

#pragma mark - Encrypt & Decrypt

+ (nullable NSData *)decrypt:(NSData *)data
          andVerifySignature:(BOOL)verify
                   usingKeys:(nullable NSArray<PGPKey *> *)verificationKeys
            passphraseForKey:(nullable NSString * _Nullable(^ __attribute__((noescape)))(PGPKey * _Nullable key))passphraseBlock
                       error:(NSError * __autoreleasing _Nullable *)error {
    NSError * decryptError = nil;
    NSError * verifyError  = nil;
    NSData * resultData = nil;
    if (verify) {
        PGPErrorCode isVerified;
        resultData = [self decrypt:data
                    verified:&isVerified
          certifyWithRootKey:NO
         usingDecryptionKeys:verificationKeys
            verificationKeys:verificationKeys
            passphraseForKey:passphraseBlock
             decryptionError:&decryptError
           verificationError:&verifyError];
        if (error){
            *error = decryptError?:verifyError;
         
        }
    }
    else {
        resultData =  [self decrypt:data
                    verified:nil
          certifyWithRootKey:NO
         usingDecryptionKeys:verificationKeys
            verificationKeys:verificationKeys
            passphraseForKey:passphraseBlock
             decryptionError:&decryptError
           verificationError:&verifyError];
        if (error){
            *error = decryptError;
        }
    }
    return resultData;
    
}


+ (nullable NSData *)decrypt:(NSData *)data
                   usingKeys:(NSArray<PGPKey *> *)decryptionKeys
          andVerifyUsingKeys:(nullable NSArray<PGPKey *> *)verificationKeys
            passphraseForKey:(nullable NSString * _Nullable(^ __attribute__((noescape)))(PGPKey * _Nullable key))passphraseBlock error:(NSError * __autoreleasing _Nullable *)error {
    if (verificationKeys) {
        PGPErrorCode isVerified;
        return [self decrypt:data
                    verified:&isVerified
          certifyWithRootKey:NO
         usingDecryptionKeys:decryptionKeys 
            verificationKeys:verificationKeys
            passphraseForKey:passphraseBlock decryptionError:error verificationError:error];
    }
    else {
        return [self decrypt:data 
                    verified:nil
          certifyWithRootKey:NO
         usingDecryptionKeys:decryptionKeys
            verificationKeys:verificationKeys
            passphraseForKey:passphraseBlock
             decryptionError:error
           verificationError:error];
    }
}

+ (nullable NSData *)decrypt:(NSData *)data 
                    verified:(PGPErrorCode * _Nullable)verified
          certifyWithRootKey:(BOOL)certifyWithRootKey
         usingDecryptionKeys:(NSArray<PGPKey *> *)decryptionKeys
            verificationKeys:(NSArray<PGPKey *> *)verificationKeys
            passphraseForKey:(nullable NSString * _Nullable(^__attribute__((noescape)))(PGPKey * _Nullable key))passphraseForKeyBlock 
             decryptionError:(NSError * __autoreleasing _Nullable *)decryptionError
           verificationError:(NSError * __autoreleasing _Nullable *)verificationError{
    
    PGPVerification * verification = nil;
    if (verified || verificationError){
        verification = [PGPVerification new];
    }
    
    NSData * result =  [self decrypt:data 
                              verify:&verification
                  certifyWithRootKey:certifyWithRootKey
                 usingDecryptionKeys:decryptionKeys
                    verificationKeys:verificationKeys
                    passphraseForKey:passphraseForKeyBlock
                     decryptionError:decryptionError];
    if (verified) *verified = verification.verificationCode;
    if (verificationError) *verificationError = verification.verificationError;
    return result;
}


+ (nullable NSData *)decrypt:(NSData *)data 
                    verified:(PGPErrorCode * _Nullable)verified
         usingDecryptionKeys:(NSArray<PGPKey *> *)decryptionKeys
            verificationKeys:(NSArray<PGPKey *> *)verificationKeys
            passphraseForKey:(nullable NSString * _Nullable(^__attribute__((noescape)))(PGPKey * _Nullable key))passphraseForKeyBlock
             decryptionError:(NSError * __autoreleasing _Nullable *)decryptionError verificationError:(NSError * __autoreleasing _Nullable *)verificationError {
    
    PGPVerification * verification = nil;
    if (verified || verificationError){
        verification = [PGPVerification new];
    }
    
    NSData * result =  [self decrypt:data 
                              verify:&verification
                  certifyWithRootKey:YES   
                 usingDecryptionKeys:decryptionKeys
                    verificationKeys:verificationKeys 
                    passphraseForKey:passphraseForKeyBlock
                     decryptionError:decryptionError];
    if (verified) *verified = verification.verificationCode == 0;
    if (verificationError) *verificationError = verification.verificationError;
    return result;
}


+ (nullable NSData *)decrypt:(NSData *)data
                      verify:(PGPVerification * __autoreleasing _Nullable * )verification
         usingDecryptionKeys:(NSArray<PGPKey *> *)decryptionKeys
            verificationKeys:(NSArray<PGPKey *> *)verificationKeys
            passphraseForKey:(nullable NSString * _Nullable(^__attribute__((noescape)))(PGPKey * _Nullable key))passphraseForKeyBlock
             decryptionError:(NSError * __autoreleasing _Nullable *)decryptionError{
    return [self decrypt:data 
                  verify:verification
      certifyWithRootKey:NO
     usingDecryptionKeys:decryptionKeys
        verificationKeys:verificationKeys
        passphraseForKey:passphraseForKeyBlock
         decryptionError:decryptionError ];
}

+ (nullable NSData *)decrypt:(NSData *)data
                      verify:(PGPVerification * __autoreleasing _Nullable *)verification
          certifyWithRootKey:(BOOL)certifyWithRootKey
         usingDecryptionKeys:(NSArray<PGPKey *> *)decryptionKeys
            verificationKeys:(NSArray<PGPKey *> *)verificationKeys
            passphraseForKey:(nullable NSString * _Nullable(^__attribute__((noescape)))(PGPKey * _Nullable key))passphraseForKeyBlock
             decryptionError:(NSError * __autoreleasing _Nullable *)decryptionError{
    PGPAssertClass(data, NSData);
    PGPAssertClass(decryptionKeys, NSArray);
    PGPAssertClass(verificationKeys, NSArray);
    
    // TODO: Decrypt all messages
    let binaryMessage = [PGPArmor convertArmoredMessage2BinaryBlocksWhenNecessary:data error:decryptionError].firstObject;
    if (!binaryMessage) {
        if (decryptionError) {
            *decryptionError = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorInvalidMessage userInfo:@{ NSLocalizedDescriptionKey: @"Unable to decrypt. Invalid message to decrypt." }];
        }
        return nil;
    }
    
    // Parse packets. Decrypt encrypted packages if needed
    let allPackets = [ObjectivePGP readPacketsFromData:binaryMessage];
    let decryptedPackets = [self decryptPacketsIfNeeded:allPackets
                                              usingKeys:decryptionKeys
                                             passphrase:passphraseForKeyBlock
                                                  error:decryptionError];
    if (decryptionError && *decryptionError) {
        return nil;
    }
    
    // If the packet list of a message contains multiple literal packets, the first literal packet should
    // be considered as the correct one and any additional literal packets should be ignored.
    let literalPacket = PGPCast([[decryptedPackets pgp_objectsPassingTest:^BOOL(PGPPacket *packet, BOOL *stop) {
        *stop = packet.tag == PGPLiteralDataPacketTag;
        return *stop;
    }] firstObject], PGPLiteralPacket);
    
    // Plaintext is available if literalPacket is available
    let plaintextData = literalPacket.literalRawData;
    if (!literalPacket || !plaintextData) {
        if (decryptionError) {
            *decryptionError = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorInvalidMessage userInfo:@{ NSLocalizedDescriptionKey: @"Unable to decrypt. Nothing to decrypt or missing private key." }];
        }
        return nil;
    }
    
    // Verify
    
    if (verification) {
        let result = [self verifyPackets:decryptedPackets
                               usingKeys:verificationKeys
                      certifyWithRootKey:certifyWithRootKey
                        passphraseForKey:passphraseForKeyBlock];
        
        *verification = result;
    }
    
    
    return plaintextData;
}

// Decrypt packets. Passphrase may be related to the key or to the symmetric encrypted message (no key in that keys)
+ (nullable NSArray<PGPPacket *> *)decryptPacketsIfNeeded:(NSArray<PGPPacket *> *)encryptedPackets usingKeys:(NSArray<PGPKey *> *)keys passphrase:(nullable NSString * _Nullable(^__attribute__((noescape)))(PGPKey * _Nullable key))passphraseBlock error:(NSError * __autoreleasing _Nullable *)error {
    // If the Symmetrically Encrypted Data packet is preceded by one or
    // more Symmetric-Key Encrypted Session Key packets, each specifies a
    // passphrase that may be used to decrypt the message.  This allows a
    // message to be encrypted to a number of public keys, and also to one
    // or more passphrases.
    PGPSymmetricAlgorithm sessionKeyAlgorithm = PGPSymmetricPlaintext;
    let packets = [NSMutableArray arrayWithArray:encryptedPackets];
    
    // 1. search for valid and known (do I have specified key?) ESK
    id <PGPEncryptedSessionKeyPacketProtocol> _Nullable eskPacket = nil;
    NSData * _Nullable sessionKeyData = nil;
    
    // Resolve session key: PGPSymetricKeyEncryptedSessionKeyPacket and/or PGPPublicKeyEncryptedSessionKeyPacket is expected
    for (PGPPacket *packet in packets) {
        if (packet.tag == PGPSymetricKeyEncryptedSessionKeyPacketTag) {
            let sESKPacket = PGPCast(packet, PGPSymetricKeyEncryptedSessionKeyPacket);
            sessionKeyAlgorithm = sESKPacket.symmetricAlgorithm;
            sessionKeyData = sESKPacket.encryptedSessionKey;
            
            // The S2K algorithm applied to the passphrase produces the session key for decrypting the file
            let passphrase = passphraseBlock ? passphraseBlock(nil) : nil;
            if (passphrase && !sESKPacket.encryptedSessionKey) {
                sessionKeyData = [sESKPacket.s2k produceSessionKeyWithPassphrase:passphrase symmetricAlgorithm:sESKPacket.symmetricAlgorithm];
            }
            
            eskPacket = sESKPacket;
        }
        
        if (packet.tag == PGPPublicKeyEncryptedSessionKeyPacketTag) {
            let pkESKPacket = PGPCast(packet, PGPPublicKeyEncryptedSessionKeyPacket);
            let decryptionKey = [PGPKeyring findKeyWithKeyID:pkESKPacket.keyID type:PGPKeyTypeSecret in:keys];
            if (!decryptionKey.secretKey) {
                // Can't proceed with this packet, but there may be other valid packet.
                continue;
            }
            
            // Found (match) secret key is used to decrypt
            var decryptionSecretKeyPacket = PGPCast([decryptionKey.secretKey decryptionPacketForKeyID:pkESKPacket.keyID error:error], PGPSecretKeyPacket);
            if (!decryptionSecretKeyPacket) {
                // Can't proceed with this packet, but there may be other valid packet.
                continue;
            } else if (decryptionKey.isEncryptedWithPassword) {
                // decrypt key with passphrase if encrypted
                let passphrase = passphraseBlock ? passphraseBlock(decryptionKey) : nil;
                if (!passphrase) {
                    // This is the match but can't proceed with this packet due to missing passphrase.
                    if (error) {
                        *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorPassphraseRequired userInfo:@{ NSLocalizedDescriptionKey: @"Unable to decrypt with the encrypted key. Decrypt key first." }];
                    }
                    PGPLogWarning(@"Can't use key \"%@\". Passphrase is required to decrypt.", decryptionSecretKeyPacket.fingerprint);
                    return nil;
                }
                
                decryptionSecretKeyPacket = [decryptionSecretKeyPacket decryptedWithPassphrase:passphrase error:error];
                if (!decryptionSecretKeyPacket || (error && *error)) {
                    PGPLogWarning(@"Can't use key \"%@\".", decryptionKey.secretKey.fingerprint);
                    decryptionSecretKeyPacket = nil;
                    continue;
                }
            }
            eskPacket = pkESKPacket;
            
            sessionKeyData = [pkESKPacket decryptSessionKeyData:PGPNN(decryptionSecretKeyPacket) sessionKeyAlgorithm:&sessionKeyAlgorithm error:error];
            NSAssert(sessionKeyAlgorithm < PGPSymmetricMax, @"Invalid session key algorithm");
        }
    }
    
    if (error && *error) {
        return nil;
    }
    
    if (eskPacket && sessionKeyData) {
        // 2 Decrypt encrypted data
        for (PGPPacket *packet in packets) {
            switch (packet.tag) {
                case PGPSymmetricallyEncryptedIntegrityProtectedDataPacketTag: {
                    // decrypt PGPSymmetricallyEncryptedIntegrityProtectedDataPacket
                    let symEncryptedDataPacket = PGPCast(packet, PGPSymmetricallyEncryptedIntegrityProtectedDataPacket);
                    let decryptedPackets = [symEncryptedDataPacket decryptWithSessionKeyAlgorithm:sessionKeyAlgorithm sessionKeyData:sessionKeyData error:error];
                    [packets addObjectsFromArray:decryptedPackets];
                } break;
                case PGPSymmetricallyEncryptedDataPacketTag: {
                    let symEncryptedDataPacket = PGPCast(packet, PGPSymmetricallyEncryptedDataPacket);
                    let decryptedPackets = [symEncryptedDataPacket decryptWithSessionKeyAlgorithm:sessionKeyAlgorithm sessionKeyData:sessionKeyData error:error];
                    [packets addObjectsFromArray:decryptedPackets];
                } break;
                default:
                    break;
            }
        }
    }
    
    // 3 append any non-encrypted literal data
    let literalPackets = [packets pgp_objectsPassingTest:^BOOL(PGPPacket *packet, BOOL *stop) {
        *stop = NO;
        return packet.tag == PGPLiteralDataPacketTag;
    }];
    [packets addObjectsFromArray:literalPackets];
    
    if (packets.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorInvalidMessage userInfo:@{ NSLocalizedDescriptionKey: @"Unable to find valid data to decrypt." }];
        }
        return encryptedPackets;
    }
    
    return packets;
}

+ (nullable NSData *)encrypt:(NSData *)dataToEncrypt addSignature:(BOOL)shouldSign usingKeys:(NSArray<PGPKey *> *)keys passphraseForKey:(nullable NSString * _Nullable(^__attribute__((noescape)))(PGPKey *key))passphraseForKeyBlock error:(NSError * __autoreleasing _Nullable *)error {
    let publicPartialKeys = [NSMutableArray<PGPPartialKey *> array];
    for (PGPKey *key in keys) {
        [publicPartialKeys pgp_addObject:key.publicKey];
    }
    
    let encryptedMessage = [NSMutableData data];
    
    // PGPPublicKeyEncryptedSessionKeyPacket goes here
    let preferredSymmeticAlgorithm = [PGPPartialKey preferredSymmetricAlgorithmForKeys:publicPartialKeys];
    
    // Random bytes as a string to be used as a key
    NSUInteger keySize = [PGPCryptoUtils keySizeOfSymmetricAlgorithm:preferredSymmeticAlgorithm];
    let sessionKeyData = [PGPCryptoUtils randomData:keySize];
    
    for (PGPPartialKey *publicPartialKey in publicPartialKeys) {
        // Encrypted Message :- Encrypted Data | ESK Sequence, Encrypted Data.
        // Encrypted Data :- Symmetrically Encrypted Data Packet | Symmetrically Encrypted Integrity Protected Data Packet
        // ESK :- Public-Key Encrypted Session Key Packet | Symmetric-Key Encrypted Session Key Packet.
        
        // ESK
        let encryptionKeyPacket = PGPCast([publicPartialKey encryptionKeyPacket:error], PGPPublicKeyPacket);
        if (!encryptionKeyPacket) {
            continue;
        }
        
        let pkESKeyPacket = [[PGPPublicKeyEncryptedSessionKeyPacket alloc] init];
        pkESKeyPacket.keyID = encryptionKeyPacket.keyID;
        pkESKeyPacket.publicKeyAlgorithm = encryptionKeyPacket.publicKeyAlgorithm;
        BOOL encrypted = [pkESKeyPacket encrypt:encryptionKeyPacket sessionKeyData:sessionKeyData sessionKeyAlgorithm:preferredSymmeticAlgorithm error:error];
        if (!encrypted || (error && *error)) {
            PGPLogDebug(@"Failed encrypt Symmetric-key Encrypted Session Key packet. Error: %@", error ? *error : @"Unknown");
            return nil;
        }
        [encryptedMessage pgp_appendData:[pkESKeyPacket export:error]];
        if (error && *error) {
            PGPLogDebug(@"Missing literal data. Error: %@", error ? *error : @"Unknown");
            return nil;
        }
        
        // TODO: find the compression type most common to the used keys
    }
    
    NSData *content;
    if (shouldSign) {
        // sign data if requested
        content = [self sign:dataToEncrypt detached:NO usingKeys:keys passphraseForKey:passphraseForKeyBlock error:error];
        let compressedPacket = [[PGPCompressedPacket alloc] initWithData:content type:PGPCompressionZLIB];
        content = [compressedPacket export:error];
    } else {
        // Prepare literal packet
        let literalPacket = [PGPLiteralPacket literalPacket:PGPLiteralPacketBinary withData:dataToEncrypt];
        literalPacket.filename = nil;
        literalPacket.timestamp = NSDate.date;
        
        let literalPacketData = [literalPacket export:error];
        if (error && *error) {
            PGPLogDebug(@"Missing literal packet data. Error: %@", *error);
            return nil;
        }
        // FIXME: do not use hardcoded value for compression type
        let compressedPacket = [[PGPCompressedPacket alloc] initWithData:literalPacketData type:PGPCompressionZLIB];
        content = [compressedPacket export:error];
    }
    
    if (!content || (error && *error)) {
        return nil;
    }
    
    let symEncryptedDataPacket = [[PGPSymmetricallyEncryptedIntegrityProtectedDataPacket alloc] init];
    [symEncryptedDataPacket encrypt:content symmetricAlgorithm:preferredSymmeticAlgorithm sessionKeyData:sessionKeyData error:error];
    
    if (error && *error) {
        return nil;
    }
    
    [encryptedMessage pgp_appendData:[symEncryptedDataPacket export:error]];
    if (error && *error) {
        return nil;
    }
    
    return encryptedMessage;
}

#pragma mark - Sign & Verify

+ (nullable NSData *)sign:(NSData *)data detached:(BOOL)detached usingKeys:(NSArray<PGPKey *> *)keys passphraseForKey:(nullable NSString * _Nullable(^__attribute__((noescape)))(PGPKey *key))passphraseBlock error:(NSError * __autoreleasing _Nullable *)error {
    PGPAssertClass(data, NSData);
    PGPAssertClass(keys, NSArray);
    
    // TODO: Use prefered hash alhorithm for key
    PGPHashAlgorithm preferedHashAlgorithm = PGPHashSHA512;
    
    // Calculate signatures signatures
    let signatures = [NSMutableArray<PGPSignaturePacket *> array];
    for (PGPKey *key in keys) {
        // Sign with the signing keys only
        if (!key.signingSecretKey) {
            continue;
        }
        // Signed Message :- Signature Packet, Literal Message
        let signaturePacket = [PGPSignaturePacket signaturePacket:PGPSignatureBinaryDocument hashAlgorithm:preferedHashAlgorithm];
        let passphrase = passphraseBlock ? passphraseBlock(key) : nil;
        if (![signaturePacket signData:data withKey:key subKey:nil passphrase:passphrase userID:nil error:error]) {
            PGPLogDebug(@"Can't sign data");
            continue;
        }
        
        [signatures pgp_addObject:signaturePacket];
    }
    
    if (signatures.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorGeneral userInfo:@{ NSLocalizedDescriptionKey: @"Unable to sign. Can't create any signature for keys." }];
            return nil;
        }
    }
    
    let outputData = [NSMutableData data];
    
    // Detached - export only signatures
    if (detached) {
        for (PGPSignaturePacket *signaturePacket in signatures) {
            NSError *exportError = nil;
            let _Nullable signaturePacketData = [signaturePacket export:&exportError];
            if (exportError) {
                if (error) {
                    *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorGeneral userInfo:@{ NSLocalizedDescriptionKey: @"Unable to sign. Can't create signature packet." }];
                }
                continue;
            }
            [outputData appendData:signaturePacketData];
        }
        // Detached return early with just signature packets.
        return outputData;
    }
    
    // Otherwise create sequence of:
    // OnePassSignature-Literal-Signature
    // Order: 1,2,3-Literal-3,2,1
    
    // Add One Pass Signature in order
    for (PGPSignaturePacket *signaturePacket in signatures) {
        // One Pass signature
        let onePassPacket = [[PGPOnePassSignaturePacket alloc] init];
        onePassPacket.signatureType = signaturePacket.type;
        onePassPacket.publicKeyAlgorithm = signaturePacket.publicKeyAlgorithm;
        onePassPacket.hashAlgorithm = signaturePacket.hashAlgoritm;
        onePassPacket.keyID = PGPNN(signaturePacket.issuerKeyID);
        onePassPacket.isNested = NO;
        NSError * _Nullable onePassExportError = nil;
        [outputData pgp_appendData:[onePassPacket export:&onePassExportError]];
        if (onePassExportError) {
            if (error) {
                *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorGeneral userInfo:@{ NSLocalizedDescriptionKey: @"Missing one signature passphrase data" }];
            }
            return nil;
        }
    }
    
    // Literal
    let literalPacket = [PGPLiteralPacket literalPacket:PGPLiteralPacketBinary withData:data];
    literalPacket.filename = nil;
    literalPacket.timestamp = [NSDate date];
    
    NSError *literalExportError = nil;
    [outputData pgp_appendData:[literalPacket export:&literalExportError]];
    if (literalExportError) {
        if (error) {
            *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorGeneral userInfo:@{ NSLocalizedDescriptionKey: @"Missing literal data" }];
        }
        return nil;
    }
    
    // Add in reversed-order
    for (PGPSignaturePacket *signaturePacket in [[signatures reverseObjectEnumerator] allObjects]) {
        // Signature coresponding to One Pass signature
        NSError *exportError = nil;
        let _Nullable signaturePacketData = [signaturePacket export:&exportError];
        if (exportError) {
            if (error) {
                *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorGeneral userInfo:@{ NSLocalizedDescriptionKey: @"Unable to sign. Can't create signature packet." }];
            }
            return nil;
        }
        [outputData pgp_appendData:signaturePacketData];
    }
    
    /*    // Compressed
     NSError *literalExportError = nil;
     let literalPacketData = [literalPacket export:&literalExportError];
     if (literalExportError) {
     if (error) {
     *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorGeneral userInfo:@{ NSLocalizedDescriptionKey: @"Missing literal data" }];
     }
     return nil;
     }*/
    
    return outputData;
}

+ (BOOL)verifySignature:(NSData *)signature usingKeys:(NSArray<PGPKey *> *)keys passphraseForKey:(nullable NSString * _Nullable(^__attribute__((noescape)))(PGPKey *key))passphraseBlock error:(NSError * __autoreleasing _Nullable *)error {
    let binaryMessages = [PGPArmor convertArmoredMessage2BinaryBlocksWhenNecessary:signature error:error];
    // TODO: Process all messages
    let binarySignature = binaryMessages.count > 0 ? binaryMessages.firstObject : nil;
    if (!binarySignature) {
        if (error) {
            *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorInvalidMessage userInfo:@{ NSLocalizedDescriptionKey: @"Invalid input data" }];
        }
        return NO;
    }
    
    // TODO: check expiration and revocation
    let packet = [PGPPacketFactory packetWithData:binarySignature offset:0 consumedBytes:nil];
    let signaturePacket = PGPCast(packet, PGPSignaturePacket);
    let issuerKeyID = signaturePacket.issuerKeyID;
    if (issuerKeyID) {
        let issuerKey = [PGPKeyring findKeyWithKeyID:issuerKeyID type:PGPKeyTypePublic in:keys];
        return issuerKey != nil;
    }
    
    return NO;
}

+ (BOOL)verify:(NSData *)signedData withSignature:(nullable NSData *)detachedSignature usingKeys:(NSArray<PGPKey *> *)keys certifyWithRootKey:(BOOL)certifyWithRootKey passphraseForKey:(nullable NSString * _Nullable(^__attribute__((noescape)))(PGPKey *key))passphraseForKeyBlock error:(NSError * __autoreleasing _Nullable *)error {
    PGPAssertClass(signedData, NSData);
    if (error) * error = nil;

    let binaryMessages = [PGPArmor convertArmoredMessage2BinaryBlocksWhenNecessary:signedData error:error];
    // TODO: Process all messages
    let binarySignedData = binaryMessages.count > 0 ? binaryMessages.firstObject : nil;
    if (!binarySignedData) {
        if (error) {
            *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorInvalidMessage userInfo:@{ NSLocalizedDescriptionKey: @"Invalid input data" }];
        }
        return NO;
    }
    
    // Use detached signature if provided.
    // In that case treat input data as blob to be verified with the signature. Don't parse it.
    if (detachedSignature) {
        let binarydetachedSignature = [PGPArmor convertArmoredMessage2BinaryBlocksWhenNecessary:detachedSignature error:error].firstObject;
        if (binarydetachedSignature) {
            let packet = [PGPPacketFactory packetWithData:binarydetachedSignature offset:0 consumedBytes:nil];
            let signaturePacket = PGPCast(packet, PGPSignaturePacket);
            let issuerKeyID = signaturePacket.issuerKeyID;
            if (issuerKeyID) {
                let issuerKey = [PGPKeyring findKeyWithKeyID:issuerKeyID type:PGPKeyTypePublic in:keys];
                if (!issuerKey) {
                    if (error) {
                        *error = [NSError errorWithDomain:PGPErrorDomain
                                                     code:PGPErrorSignatureVerificationMissingKey
                                                 userInfo:@{ NSLocalizedDescriptionKey: @"Unable to check signature. No public key.",
                                                             PGPMissingPublicKeyIdUserInfoKey:issuerKeyID}];
                    }
                    return NO;
                }
                return [signaturePacket verifyData:binarySignedData publicKey:issuerKey error:error];
            }
        }
        return NO;
    }
    
    // Otherwise treat input data as PGP Message and process for literal data.
    
    // Propably not the best solution when it comes to memory consumption.
    // Literal data is copied more than once (first at parse phase, then when is come to build signature packet data.
    // I belive this is unecessary but require more work. Schedule to v2.0.
    
    // search for signature packet
    var accumulatedPackets = [self readPacketsFromData:binarySignedData];
    
    //Try to decrypt first, in case of encrypted message inside
    //Not every message needs decryption though! Check for ESK to reason about it
    BOOL isEncrypted = [[accumulatedPackets pgp_objectsPassingTest:^BOOL(PGPPacket *packet, BOOL *stop) {
        BOOL found = (packet.tag == PGPPublicKeyEncryptedSessionKeyPacketTag) || (packet.tag == PGPSymetricKeyEncryptedSessionKeyPacketTag);
        *stop = found;
        return found;
    }] firstObject] != nil;
    
    if (isEncrypted) {
        NSError *decryptError = nil;
        accumulatedPackets = [[self.class decryptPacketsIfNeeded:accumulatedPackets usingKeys:keys passphrase:passphraseForKeyBlock error:&decryptError] mutableCopy];
        if (decryptError) {
            if (error) {
                *error = [decryptError copy];
            }
            return NO;
        }
    }
    let verifyResult =  [self verifyPackets:accumulatedPackets
                            usingKeys:keys
                   certifyWithRootKey:certifyWithRootKey
                     passphraseForKey:passphraseForKeyBlock];
    
    if (error) *error = verifyResult.verificationError;
    return verifyResult.verificationCode == 0;
}

+ (BOOL)verify:(NSData *)signedData withSignature:(nullable NSData *)detachedSignature usingKeys:(NSArray<PGPKey *> *)keys passphraseForKey:(nullable NSString * _Nullable(^__attribute__((noescape)))(PGPKey *key))passphraseForKeyBlock error:(NSError * __autoreleasing _Nullable *)error {
    return [self verify:signedData 
          withSignature:detachedSignature
              usingKeys:keys
     certifyWithRootKey:NO
       passphraseForKey:passphraseForKeyBlock
                  error:error];
}
+ (PGPVerification*) verifyPackets:(NSArray *)accumulatedPackets usingKeys:(NSArray<PGPKey *> *)keys certifyWithRootKey:(BOOL)certifyWithRootKey passphraseForKey:(nullable NSString * _Nullable(^__attribute__((noescape)))(PGPKey *key))passphraseForKeyBlock {
    
    let verResult = PGPVerification.new;
   
    // PGPSignaturePacket * _Nullable signaturePacket = nil;
    let signatures = [NSMutableArray<PGPSignaturePacket *> array];
    PGPLiteralPacket * _Nullable literalPacket = nil;
    
    int onePassSignatureCount = 0;
    int signatureCount = 0;
    for (PGPPacket *packet in accumulatedPackets) {
        switch (packet.tag) {
            case PGPCompressedDataPacketTag:
                // ignore here
                break;
            case PGPOnePassSignaturePacketTag:
                // ignore here, but should check if the number of one-pass-sig is equal to attached signatures
                onePassSignatureCount++;
                break;
            case PGPLiteralDataPacketTag:
                // Only first literal packet is considered as correct
                if (!literalPacket) {
                    literalPacket = PGPCast(packet, PGPLiteralPacket);
                }
                break;
            case PGPSignaturePacketTag: {
                let signaturePacket = PGPCast(packet, PGPSignaturePacket);
                [signatures pgp_addObject:signaturePacket];
                signatureCount++;
            }
                break;
            default:
                break;
        }
    }

    if (onePassSignatureCount != signatureCount) {
        verResult.verificationCode = PGPErrorMissingSignature;
        verResult.verificationError = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorMissingSignature userInfo:@{ NSLocalizedDescriptionKey: @"Message is not properly signed." }];
        return verResult;
    }

    if (signatures.count == 0) {
        verResult.verificationCode = PGPErrorNotSigned;
        verResult.verificationError  = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorNotSigned userInfo:@{ NSLocalizedDescriptionKey: @"Message is not signed." }];
        return verResult;
    }

    if (!literalPacket) {
        verResult.verificationCode = PGPErrorInvalidSignature;
        verResult.verificationError = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorInvalidSignature userInfo:@{ NSLocalizedDescriptionKey: @"Message is not valid. Missing literal data." }];
        return verResult;
    }


    // Validate signatures
    BOOL isValid = NO;

    for (PGPSignaturePacket *signaturePacket in signatures) {
        let signedLiteralData = literalPacket.literalRawData;
        if (signedLiteralData) {
            let issuerKeyID = signaturePacket.issuerKeyID;
            if (issuerKeyID != nil) {
                let issuerKey = [PGPKeyring findKeyWithKeyID:issuerKeyID type:PGPKeyTypePublic in:keys];
                if (issuerKey == nil) {
                    verResult.verificationCode = PGPErrorInvalidSignature;
                    verResult.verificationError =  [NSError errorWithDomain:PGPErrorDomain
                                                                       code:PGPErrorSignatureVerificationMissingKey
                                                                   userInfo:@{ NSLocalizedDescriptionKey: @"Unable to check signature. No public key." ,
                                                                               PGPMissingPublicKeyIdUserInfoKey:issuerKeyID }];
                    return verResult;
                }
                NSError * error = nil;
                isValid = [signaturePacket verifyData:signedLiteralData publicKey:issuerKey error:&error];
                if (!isValid){
                    verResult.verificationCode = error.code;
                    verResult.verificationError = error;
                }
                if (isValid && certifyWithRootKey) {
                    isValid = [self verifyCertification:issuerKey usingKeys:keys error:&error];
                    if (!isValid){
                        verResult.verificationCode = error.code;;
                        verResult.verificationError = error;
                    }
                }
                if (isValid){
                    verResult.keyID = issuerKey.keyID;
                }
            }
        }
    }

    return verResult;
}

+ (BOOL)verifyCertification:(PGPKey*)issuerKey usingKeys:(NSArray<PGPKey *> *)keys error:(NSError * __autoreleasing _Nullable *)error {
    BOOL isValid = YES;
    // Add additional signature check
    PGPUser* user = PGPCast(issuerKey.publicKey.users[0], PGPUser);
                   
    if (user.otherSignatures.count > 0) {
        PGPSignaturePacket* userSignature = user.otherSignatures[0];
        if (!userSignature) {
           if (error) {
               *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorMissingPublicKeySignature userInfo:@{ NSLocalizedDescriptionKey: @"Unable to check signature. User has not signed with trusted CA." }];
           }
           return NO;
       }
       
       PGPKeyID* rootKeyID = userSignature.issuerKeyID;
       if (rootKeyID) {
           let rootKey = [PGPKeyring findKeyWithKeyID:rootKeyID type:PGPKeyTypePublic in:keys];
           if (!rootKey) {
               if (error) {
                   *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorMissingRootPublicKey userInfo:@{ NSLocalizedDescriptionKey: @"Unable to check signature. Root CA is not found or invalid." }];
               }
               return NO;
           }
           // TODO: check expiration
           isValid &= [userSignature verifyCertificateSignature:issuerKey rootCert:rootKey userID:issuerKey.publicKey.users[0].userID error:error];
           
           if (isValid) {
               return YES;
           }
           else {
               if (error) {
                   *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorInvalidSignature userInfo:@{ NSLocalizedDescriptionKey: @"Unable to check signature. Signature is invalid." }];
               }
           }
       }
    }
    else {
        isValid = NO;
        if (error) {
            *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorMissingPublicKeySignature userInfo:@{ NSLocalizedDescriptionKey: @"Unable to check signature. Public key signature is missing." }];
        }
    }
    
    return isValid;
}

+ (nullable NSArray<PGPKey *> *)readKeysFromPath:(NSString *)path error:(NSError * __autoreleasing _Nullable *)error {
    NSString *fullPath = [path stringByExpandingTildeInPath];

    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDirectory] || isDirectory) {
        if (error) {
            *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorInvalidMessage userInfo:@{NSLocalizedDescriptionKey: @"Can't read keys. Invalid input."}];
        }
        return nil;
    }

    let fileData = [NSData dataWithContentsOfFile:fullPath options:NSDataReadingMappedIfSafe | NSDataReadingUncached error:error];
    if (!fileData || (error && *error)) {
        if (error) {
            *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorInvalidMessage userInfo:@{NSLocalizedDescriptionKey: @"Can't read keys. Invalid input."}];
        }
        return nil;
    }

    return [self readKeysFromData:fileData error:error];
}

+ (nullable NSArray<PGPKey *> *)readKeysFromData:(NSData *)fileData error:(NSError * __autoreleasing _Nullable *)error {
    PGPAssertClass(fileData, NSData);

    var keys = [NSArray<PGPKey *> array];

    if (fileData.length == 0) {
        PGPLogError(@"Empty input data");
        if (error) {
            *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorInvalidMessage userInfo:@{NSLocalizedDescriptionKey: @"Can't read keys. Invalid input."}];
        }
        return nil;
    };

    let binRingData = [PGPArmor convertArmoredMessage2BinaryBlocksWhenNecessary:fileData error:error];
    if (!binRingData || binRingData.count == 0) {
        PGPLogError(@"Invalid input data");
        if (error) {
            *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorInvalidMessage userInfo:@{NSLocalizedDescriptionKey: @"Can't read keys. Invalid input."}];
        }
        return nil;
    }

    for (NSData *data in binRingData) {
        let readPartialKeys = [self readPartialKeysFromData:data];
        for (PGPPartialKey *key in readPartialKeys) {
            keys = [PGPKeyring addOrUpdatePartialKey:key inContainer:keys];
        }
    }

    return keys;
}

+ (nullable NSArray<PGPKeyID *> *)recipientsKeyIDForMessage:(NSData *)data error:(NSError * __autoreleasing _Nullable *)error {
    PGPAssertClass(data, NSData);

    // TODO: Decrypt all messages
    let binaryMessage = [PGPArmor convertArmoredMessage2BinaryBlocksWhenNecessary:data error:error].firstObject;
    if (!binaryMessage) {
        if (error) {
            *error = [NSError errorWithDomain:PGPErrorDomain code:PGPErrorInvalidMessage userInfo:@{ NSLocalizedDescriptionKey: @"Unable to decrypt. Invalid message to decrypt." }];
        }
        return nil;
    }

    // parse packets
    let foundKeys = [NSMutableOrderedSet<PGPKeyID *> orderedSetWithCapacity:1];
    var packets = [ObjectivePGP readPacketsFromData:binaryMessage];
    for (PGPPacket *packet in packets) {
        switch (packet.tag) {
            case PGPPublicKeyEncryptedSessionKeyPacketTag: {
                let publicKeyEncrypteSessionKey = PGPCast(packet, PGPPublicKeyEncryptedSessionKeyPacket);
                [foundKeys addObject:publicKeyEncrypteSessionKey.keyID];
            } break;
            case PGPSignaturePacketTag: {
                let signaturePacket = PGPCast(packet,PGPSignaturePacket);
                [foundKeys addObject:signaturePacket.issuerKeyID];
            } break;
            default:
                break;
        }
    }
    return foundKeys.count > 0 ? foundKeys.array : nil;
}

#pragma mark - Private

+ (NSArray<PGPPacket *> *)readPacketsFromData:(NSData *)data {
    return [self readPacketsFromData:data offset:0];
}

+ (NSArray<PGPPacket *> *)readPacketsFromData:(NSData *)data offset:(NSUInteger)offsetPosition {
    PGPAssertClass(data, NSData);

    if (data.length == 0) {
        return @[];
    }

    let accumulatedPackets = [NSMutableArray<PGPPacket *> array];
    NSUInteger offset = offsetPosition;
    NSUInteger consumedBytes = 0;
    while (offset < data.length) {
        @autoreleasepool {
            let packet = [PGPPacketFactory packetWithData:data offset:offset consumedBytes:&consumedBytes];
            [accumulatedPackets pgp_addObject:packet];

            // A compressed Packet contains more packets.
            let _Nullable compressedPacket = PGPCast(packet, PGPCompressedPacket);
            if (compressedPacket) {
                let uncompressedPackets = [self readPacketsFromData:compressedPacket.decompressedData offset:0];
                [accumulatedPackets addObjectsFromArray:uncompressedPackets ?: @[]];
            }

            // corrupted data. Move by one byte in hope we find some packet there, or EOF.
            if (consumedBytes == 0) {
                offset++;
            }
            offset += consumedBytes;
        }
    }

    return accumulatedPackets;
}

+ (NSArray<PGPPartialKey *> *)readPartialKeysFromData:(NSData *)messageData {
    let partialKeys = [NSMutableArray<PGPPartialKey *> array];
    let accumulatedPackets = [NSMutableArray<PGPPacket *> array];
    NSUInteger position = 0;
    NSUInteger consumedBytes = 0;

    while (position < messageData.length) {
        @autoreleasepool {
            let _Nullable packet = [PGPPacketFactory packetWithData:messageData offset:position consumedBytes:&consumedBytes];
            if (!packet) {
                position += (consumedBytes > 0) ? consumedBytes : 1;
                continue;
            }

            if ((accumulatedPackets.count > 1) && ((packet.tag == PGPPublicKeyPacketTag) || (packet.tag == PGPSecretKeyPacketTag))) {
                PGPPublicKeyPacket *pubPacket = (PGPPublicKeyPacket*) packet;
                if ((pubPacket.isSupported) ) {
                    let partialKey = [[PGPPartialKey alloc] initWithPackets:accumulatedPackets];
                    [partialKeys addObject:partialKey];
                }
                [accumulatedPackets removeAllObjects];
            }

            [accumulatedPackets pgp_addObject:packet];
            position += consumedBytes;
        }
    }

    
    if (accumulatedPackets.count > 1) {
        for (PGPPacket *p in accumulatedPackets) {
            if (p.tag == PGPPublicKeyPacketTag || p.tag == PGPSecretKeyPacketTag) {
                PGPPublicKeyPacket *pubPacket = (PGPPublicKeyPacket*) p;
                if ((pubPacket.isSupported) ) {
                    let key = [[PGPPartialKey alloc] initWithPackets:accumulatedPackets];
                    [partialKeys addObject:key];
                }
            }
        }
        [accumulatedPackets removeAllObjects];
    }

    return partialKeys;
}

@end

NS_ASSUME_NONNULL_END

