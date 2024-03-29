unit UAccounts;

{$IFDEF FPC}
{$MODE Delphi}
{$ENDIF}
{ Copyright (c) 2016 by Albert Molina

  Distributed under the MIT software license, see the accompanying file LICENSE
  or visit http://www.opensource.org/licenses/mit-license.php.

  This unit is a part of Pascal Coin, a P2P crypto currency without need of
  historical operations.

  If you like it, consider a donation using BitCoin:
  16K3HCZRhFUtM8GdWRcfKeaa6KsuyxZaYk

}

interface

uses
    Classes, UConst, UCrypto, SyncObjs, UThread, UBaseTypes, UCommon;
{$I config.inc}

Type
    TAccountKey = TECDSA_Public;
    PAccountKey = ^TAccountKey;

    TAccountState = (as_Unknown, as_Normal, as_ForSale);

    TAccountInfo = Record
        state: TAccountState;
        accountKey: TAccountKey;
        // Trade info, only when state=as_ForSale
        locked_until_block: Cardinal; // 0 = Not locked
        price: UInt64; // 0 = invalid price
        account_to_pay: Cardinal; // <> itself
        new_publicKey: TAccountKey;
    end;

    TOperationBlock = Record
        block: Cardinal;
        account_key: TAccountKey;
        reward: UInt64;
        fee: UInt64;
        protocol_version: Word; // Protocol version
        protocol_available: Word; // Used to upgrade protocol
        timestamp: Cardinal; // Timestamp creation
        compact_target: Cardinal; // Target in compact form
        nonce: Cardinal; // Random value to generate a new P-o-W
        block_payload: TRawBytes; // RAW Payload that a miner can include to a blockchain
        initial_safe_box_hash: TRawBytes; // RAW Safe Box Hash value (32 bytes, it's a Sha256)
        operations_hash: TRawBytes; // RAW sha256 (32 bytes) of Operations
        proof_of_work: TRawBytes; // RAW Double Sha256
    end;

    { TPascalCoinProtocol }

    TPascalCoinProtocol = Class
    public
        Class Function GetRewardForNewLine(line_index: Cardinal): UInt64;
        Class Function TargetToCompact(target: TRawBytes): Cardinal;
        Class Function TargetFromCompact(encoded: Cardinal): TRawBytes;
        Class Function GetNewTarget(vteorical, vreal: Cardinal; Const actualTarget: TRawBytes): TRawBytes;
        Class Procedure CalcProofOfWork_Part1(const operationBlock: TOperationBlock; var Part1: TRawBytes);
        Class Procedure CalcProofOfWork_Part3(const operationBlock: TOperationBlock; var Part3: TRawBytes);
        Class Procedure CalcProofOfWork(const operationBlock: TOperationBlock; var PoW: TRawBytes);
    end;

    { TAccountComp }

    TAccountComp = Class
    private
    public
        Class Function IsValidAccountKey(const account: TAccountKey; var errors: AnsiString): Boolean;
        Class Function IsValidAccountInfo(const accountInfo: TAccountInfo; var errors: AnsiString): Boolean;
        Class Function IsAccountForSale(const accountInfo: TAccountInfo): Boolean;
        Class Function IsAccountForSaleAcceptingTransactions(const accountInfo: TAccountInfo): Boolean;
        Class Function GetECInfoTxt(Const EC_OpenSSL_NID: Word): AnsiString;
        Class Procedure ValidsEC_OpenSSL_NID(list: TList);
        Class Function AccountKey2RawString(const account: TAccountKey): TRawBytes; overload;
        Class procedure AccountKey2RawString(const account: TAccountKey; var dest: TRawBytes); overload;
        Class Function RawString2Accountkey(const rawaccstr: TRawBytes): TAccountKey; overload;
        Class procedure RawString2Accountkey(const rawaccstr: TRawBytes; var dest: TAccountKey); overload;
        Class Function PrivateToAccountkey(key: TECPrivateKey): TAccountKey;
        Class Function IsAccountBlockedByProtocol(account_number, blocks_count: Cardinal): Boolean;
        Class Function EqualAccountInfos(const accountInfo1, accountInfo2: TAccountInfo): Boolean;
        Class Function EqualAccountKeys(const account1, account2: TAccountKey): Boolean;
        Class Function AccountNumberToAccountTxtNumber(account_number: Cardinal): AnsiString;
        Class function AccountTxtNumberToAccountNumber(Const account_txt_number: AnsiString; var account_number: Cardinal): Boolean;
        Class function FormatMoney(Money: Int64): AnsiString;
        Class Function TxtToMoney(Const moneytxt: AnsiString; var Money: Int64): Boolean;
        Class Function AccountKeyFromImport(Const HumanReadable: AnsiString; var account: TAccountKey; var errors: AnsiString): Boolean;
        Class Function AccountPublicKeyExport(Const account: TAccountKey): AnsiString;
        Class Function AccountPublicKeyImport(Const HumanReadable: AnsiString; var account: TAccountKey; var errors: AnsiString): Boolean;
        Class Function AccountBlock(Const account_number: Cardinal): Cardinal;
        Class Function AccountInfo2RawString(const accountInfo: TAccountInfo): TRawBytes; overload;
        Class procedure AccountInfo2RawString(const accountInfo: TAccountInfo; var dest: TRawBytes); overload;
        Class Function RawString2AccountInfo(const rawaccstr: TRawBytes): TAccountInfo; overload;
        Class procedure RawString2AccountInfo(const rawaccstr: TRawBytes; var dest: TAccountInfo); overload;
        Class Function IsAccountLocked(const accountInfo: TAccountInfo; blocks_count: Cardinal): Boolean;
        Class procedure SaveTOperationBlockToStream(const stream: TStream; const operationBlock: TOperationBlock);
        Class Function LoadTOperationBlockFromStream(const stream: TStream; var operationBlock: TOperationBlock): Boolean;
    End;

    TAccount = Record
        account: Cardinal; // FIXED value. Account number
        accountInfo: TAccountInfo;
        balance: UInt64; // Balance, always >= 0
        updated_block: Cardinal; // Number of block where was updated
        n_operation: Cardinal; // count number of owner operations (when receive, this is not updated)
        name: TRawBytes; // Protocol 2. Unique name
        account_type: Word; // Protocol 2. Layer 2 use case
        previous_updated_block: Cardinal;
        // New Build 1.0.8 -> Only used to store this info to storage. It helps App to search when an account was updated. NOT USED FOR HASH CALCULATIONS!
    End;

    PAccount = ^TAccount;

    {
      Protocol 2:
      Introducing OperationBlock info on the safebox, this will allow checkpointing a safebox because
      each row of the safebox (TBlockAccount) will have data about how to calculate
      its PoW, so next row will use row-1 info to check it's good generated thanks to PoW

      This solution does not include operations, but include operations_hash value,
      that is a SHA256 of operations.

      If someone wants to change the safebox and spam, will need to find values
      to alter safebox accounts of last checkpoint and also find new blocks prior
      to honest nodes, that will be only accepted by nodes that does not have
      last blocks (only fresh nodes). This is a very hard job and not efficient
      because usually there will be few new fresh nodes per period, so only
      can spam new fresh nodes because old nodes does not need to download
      a checkpointing.
      This solution was created by Herman Schoenfeld (Thanks!)
    }

    TBlockAccount = Record
        blockchainInfo: TOperationBlock;
        accounts: Array [0 .. CT_AccountsPerBlock - 1] of TAccount;
        block_hash: AnsiString; // Calculated on every block change (on create and on accounts updated)
        accumulatedWork: UInt64; // Accumulated work (previous + target) this value can be calculated.
    end;

    TCardinalsArray = Array of Cardinal;

    { Estimated TAccount size:
      4 + 200 (max aprox) + 8 + 4 + 4 = 220 max aprox
      Estimated TBlockAccount size:
      4 + (5 * 220) + 4 + 32 = 1140 max aprox
    }

    TOrderedCardinalList = Class
    private
        FOrderedList: TList;
        FDisabledsCount: Integer;
        FModifiedWhileDisabled: Boolean;
        FOnListChanged: TNotifyEvent;
        Procedure NotifyChanged;
    public
        Constructor Create;
        Destructor Destroy; override;
        Function Add(Value: Cardinal): Integer;
        Procedure Remove(Value: Cardinal);
        Procedure Clear;
        Function Get(index: Integer): Cardinal;
        Function Count: Integer;
        Function Find(const Value: Cardinal; var index: Integer): Boolean;
        Procedure Disable;
        Procedure Enable;
        Property OnListChanged: TNotifyEvent read FOnListChanged write FOnListChanged;
        Procedure CopyFrom(Sender: TOrderedCardinalList);
        Function ToArray: TCardinalsArray;
    End;

    TPCSafeBox = Class;

    TPCSafeBoxHeader = Record
        protocol: Word;
        startBlock, endBlock, blocksCount: Cardinal;
        safeBoxHash: TRawBytes;
    end;

    // This is a class to quickly find accountkeys and their respective account number/s
    TOrderedAccountKeysList = Class
    Private
        FAutoAddAll: Boolean;
        FAccountList: TPCSafeBox;
        FOrderedAccountKeysList: TList; // An ordered list of pointers to quickly find account keys in account list
        Function Find(Const accountKey: TAccountKey; var index: Integer): Boolean;
        function GetAccountKeyList(index: Integer): TOrderedCardinalList;
        function GetAccountKey(index: Integer): TAccountKey;
    protected
        Procedure ClearAccounts(RemoveAccountList: Boolean);
    public
        Constructor Create(AccountList: TPCSafeBox; AutoAddAll: Boolean);
        Destructor Destroy; override;
        Procedure AddAccountKey(Const accountKey: TAccountKey);
        Procedure RemoveAccountKey(Const accountKey: TAccountKey);
        Procedure AddAccounts(Const accountKey: TAccountKey; const accounts: Array of Cardinal);
        Procedure RemoveAccounts(Const accountKey: TAccountKey; const accounts: Array of Cardinal);
        Function IndexOfAccountKey(Const accountKey: TAccountKey): Integer;
        Property AccountKeyList[index: Integer]: TOrderedCardinalList read GetAccountKeyList;
        Property accountKey[index: Integer]: TAccountKey read GetAccountKey;
        Function Count: Integer;
        Property SafeBox: TPCSafeBox read FAccountList;
        Procedure Clear;
    End;

    // Maintains a TRawBytes (AnsiString) list ordered to quick search withoud duplicates
    TOrderedRawList = Class
    private
        FList: TList;
        Function Find(const RawData: TRawBytes; var index: Integer): Boolean;
    public
        Constructor Create;
        Destructor Destroy; Override;
        Procedure Clear;
        Function Add(Const RawData: TRawBytes; tagValue: Integer = 0): Integer;
        Function Count: Integer;
        Function Get(index: Integer): TRawBytes;
        Procedure Delete(index: Integer);
        procedure SetTag(Const RawData: TRawBytes; newTagValue: Integer);
        function GetTag(Const RawData: TRawBytes): Integer; overload;
        function GetTag(index: Integer): Integer; overload;
        Function IndexOf(Const RawData: TRawBytes): Integer;
    End;

    // SafeBox is a box that only can be updated using SafeBoxTransaction, and this
    // happens only when a new BlockChain is included. After this, a new "SafeBoxHash"
    // is created, so each SafeBox has a unique SafeBoxHash

    { TPCSafeBox }

    TPCSafeBox = Class
    private
        FBlockAccountsList: TList;
        FListOfOrderedAccountKeysList: TList;
        FBufferBlocksHash: TRawBytes;
        FOrderedByName: TOrderedRawList;
        FTotalBalance: Int64;
        FTotalFee: Int64;
        FSafeBoxHash: TRawBytes;
        FLock: TPCCriticalSection; // Thread safe
        FWorkSum: UInt64;
        FCurrentProtocol: Integer;
        Procedure SetAccount(account_number: Cardinal; const newAccountInfo: TAccountInfo; const newName: TRawBytes; newType: Word; newBalance: UInt64;
          newN_operation: Cardinal);
        Procedure AccountKeyListAddAccounts(Const accountKey: TAccountKey; const accounts: Array of Cardinal);
        Procedure AccountKeyListRemoveAccount(Const accountKey: TAccountKey; const accounts: Array of Cardinal);
    protected
        Function AddNew(Const blockChain: TOperationBlock): TBlockAccount;
        function DoUpgradeToProtocol2: Boolean;
    public
        Constructor Create;
        Destructor Destroy; override;
        function AccountsCount: Integer;
        Function blocksCount: Integer;
        Procedure CopyFrom(accounts: TPCSafeBox);
        Class Function CalcBlockHash(const block: TBlockAccount; useProtocol2Method: Boolean): TRawBytes;
        Class Function BlockAccountToText(Const block: TBlockAccount): AnsiString;
        Function LoadSafeBoxFromStream(stream: TStream; checkAll: Boolean; var LastReadBlock: TBlockAccount; var errors: AnsiString): Boolean;
        Class Function LoadSafeBoxStreamHeader(stream: TStream; var sbHeader: TPCSafeBoxHeader): Boolean;
        Class Function SaveSafeBoxStreamHeader(stream: TStream; protocol: Word; OffsetStartBlock, OffsetEndBlock, CurrentSafeBoxBlocksCount: Cardinal): Boolean;
        Class Function MustSafeBoxBeSaved(blocksCount: Cardinal): Boolean;
        Procedure SaveSafeBoxBlockToAStream(stream: TStream; nBlock: Cardinal);
        Procedure SaveSafeBoxToAStream(stream: TStream; FromBlock, ToBlock: Cardinal);
        class Function CopySafeBoxStream(Source, dest: TStream; FromBlock, ToBlock: Cardinal; var errors: AnsiString): Boolean;
        class Function ConcatSafeBoxStream(Source1, Source2, dest: TStream; var errors: AnsiString): Boolean;
        class function ValidAccountName(const new_name: TRawBytes; var errors: AnsiString): Boolean;

        Function IsValidNewOperationsBlock(Const newOperationBlock: TOperationBlock; checkSafeBoxHash: Boolean; var errors: AnsiString): Boolean;
        Function GetActualTargetHash(UseProtocolV2: Boolean): TRawBytes;
        Function GetActualCompactTargetHash(UseProtocolV2: Boolean): Cardinal;
        Function FindAccountByName(aName: AnsiString): Integer;

        Procedure Clear;
        Function account(account_number: Cardinal): TAccount;
        Function block(block_number: Cardinal): TBlockAccount;
        Function CalcSafeBoxHash: TRawBytes;
        Function CalcBlockHashRateInKhs(block_number: Cardinal; Previous_blocks_average: Cardinal): Int64;
        Property TotalBalance: Int64 read FTotalBalance;
        Procedure StartThreadSafe;
        Procedure EndThreadSave;
        Property safeBoxHash: TRawBytes read FSafeBoxHash;
        Property WorkSum: UInt64 read FWorkSum;
        Property CurrentProtocol: Integer read FCurrentProtocol;
        function CanUpgradeToProtocol2: Boolean;
        procedure CheckMemory;
    End;

    TOrderedAccountList = Class
    private
        FList: TList;
        Function Find(const account_number: Cardinal; var index: Integer): Boolean;
    public
        Constructor Create;
        Destructor Destroy; Override;
        Procedure Clear;
        Function Add(Const account: TAccount): Integer;
        Function Count: Integer;
        Function Get(index: Integer): TAccount;
    End;

    { TPCSafeBoxTransaction }

    TPCSafeBoxTransaction = Class
    private
        FOrderedList: TOrderedAccountList;
        FFreezedAccounts: TPCSafeBox;
        FTotalBalance: Int64;
        FTotalFee: Int64;
        FOldSafeBoxHash: TRawBytes;
        FAccountNames_Deleted: TOrderedRawList;
        FAccountNames_Added: TOrderedRawList;
        Function GetInternalAccount(account_number: Cardinal): PAccount;
    protected
    public
        Constructor Create(SafeBox: TPCSafeBox);
        Destructor Destroy; override;
        Function TransferAmount(Sender, target: Cardinal; n_operation: Cardinal; amount, fee: UInt64; var errors: AnsiString): Boolean;
        Function UpdateAccountInfo(signer_account, signer_n_operation, target_account: Cardinal; accountInfo: TAccountInfo; newName: TRawBytes; newType: Word;
          fee: UInt64; var errors: AnsiString): Boolean;
        Function BuyAccount(buyer, account_to_buy, seller: Cardinal; n_operation: Cardinal; amount, account_price, fee: UInt64;
          const new_account_key: TAccountKey; var errors: AnsiString): Boolean;
        Function Commit(Const operationBlock: TOperationBlock; var errors: AnsiString): Boolean;
        Function account(account_number: Cardinal): TAccount;
        Procedure Rollback;
        Function CheckIntegrity: Boolean;
        Property FreezedSafeBox: TPCSafeBox read FFreezedAccounts;
        Property TotalFee: Int64 read FTotalFee;
        Property TotalBalance: Int64 read FTotalBalance;
        Procedure CopyFrom(transaction: TPCSafeBoxTransaction);
        Procedure CleanTransaction;
        Function ModifiedCount: Integer;
        Function Modified(index: Integer): TAccount;
    End;

    TStreamOp = Class
    public
        class Function WriteAnsiString(stream: TStream; const Value: AnsiString): Integer; overload;
        class Function ReadAnsiString(stream: TStream; var Value: AnsiString): Integer; overload;
        class Function WriteAccountKey(stream: TStream; const Value: TAccountKey): Integer;
        class Function ReadAccountKey(stream: TStream; var Value: TAccountKey): Integer;
    End;

Const
    CT_OperationBlock_NUL: TOperationBlock = (block: 0; account_key: (EC_OpenSSL_NID: 0; x: ''; y: ''); reward: 0; fee: 0; protocol_version: 0;
      protocol_available: 0; timestamp: 0; compact_target: 0; nonce: 0; block_payload: ''; operations_hash: ''; proof_of_work: '');
    CT_AccountInfo_NUL: TAccountInfo = (state: as_Unknown; accountKey: (EC_OpenSSL_NID: 0; x: ''; y: ''); locked_until_block: 0; price: 0; account_to_pay: 0;
      new_publicKey: (EC_OpenSSL_NID: 0; x: ''; y: ''));
    CT_Account_NUL: TAccount = (account: 0; accountInfo: (state: as_Unknown; accountKey: (EC_OpenSSL_NID: 0; x: ''; y: ''); locked_until_block: 0; price: 0;
      account_to_pay: 0; new_publicKey: (EC_OpenSSL_NID: 0; x: ''; y: '')); balance: 0; updated_block: 0; n_operation: 0; name: ''; account_type: 0;
      previous_updated_block: 0);
    CT_BlockAccount_NUL: TBlockAccount = (blockchainInfo: (block: 0; account_key: (EC_OpenSSL_NID: 0; x: ''; y: ''); reward: 0; fee: 0; protocol_version: 0;
      protocol_available: 0; timestamp: 0; compact_target: 0; nonce: 0; block_payload: ''; operations_hash: ''; proof_of_work: '');
      accounts: ((account: 0; accountInfo: (state: as_Unknown; accountKey: (EC_OpenSSL_NID: 0; x: ''; y: ''); locked_until_block: 0; price: 0;
      account_to_pay: 0; new_publicKey: (EC_OpenSSL_NID: 0; x: ''; y: '')); balance: 0; updated_block: 0; n_operation: 0; name: ''; account_type: 0;
      previous_updated_block: 0), (account: 0; accountInfo: (state: as_Unknown; accountKey: (EC_OpenSSL_NID: 0; x: ''; y: ''); locked_until_block: 0; price: 0;
      account_to_pay: 0; new_publicKey: (EC_OpenSSL_NID: 0; x: ''; y: '')); balance: 0; updated_block: 0; n_operation: 0; name: ''; account_type: 0;
      previous_updated_block: 0), (account: 0; accountInfo: (state: as_Unknown; accountKey: (EC_OpenSSL_NID: 0; x: ''; y: ''); locked_until_block: 0; price: 0;
      account_to_pay: 0; new_publicKey: (EC_OpenSSL_NID: 0; x: ''; y: '')); balance: 0; updated_block: 0; n_operation: 0; name: ''; account_type: 0;
      previous_updated_block: 0), (account: 0; accountInfo: (state: as_Unknown; accountKey: (EC_OpenSSL_NID: 0; x: ''; y: ''); locked_until_block: 0; price: 0;
      account_to_pay: 0; new_publicKey: (EC_OpenSSL_NID: 0; x: ''; y: '')); balance: 0; updated_block: 0; n_operation: 0; name: ''; account_type: 0;
      previous_updated_block: 0), (account: 0; accountInfo: (state: as_Unknown; accountKey: (EC_OpenSSL_NID: 0; x: ''; y: ''); locked_until_block: 0; price: 0;
      account_to_pay: 0; new_publicKey: (EC_OpenSSL_NID: 0; x: ''; y: '')); balance: 0; updated_block: 0; n_operation: 0; name: ''; account_type: 0;
      previous_updated_block: 0)); block_hash: ''; accumulatedWork: 0);

    CT_SafeBoxChunkIdentificator = 'SafeBoxChunk';
    CT_PCSafeBoxHeader_NUL: TPCSafeBoxHeader = (protocol: 0; startBlock: 0; endBlock: 0; blocksCount: 0; safeBoxHash: '');

implementation

uses
    SysUtils, ULog, UOpenSSLdef, UOpenSSL;

{ TPascalCoinProtocol }

class function TPascalCoinProtocol.GetNewTarget(vteorical, vreal: Cardinal; Const actualTarget: TRawBytes): TRawBytes;
Var
    bnact, bnaux, bnmindiff, bnremainder, bn: TBigNum;
    ts1, ts2: Cardinal;
    tsTeorical, tsReal, factor1000, factor1000Min, factor1000Max: Int64;
begin
    { Given a teorical time in seconds (vteorical>0) and a real time in seconds (vreal>0)
      and an actual target, calculates a new target
      by % of difference of teorical vs real.

      Increment/decrement is adjusted to +-200% in a full CT_CalcNewTargetBlocksAverage round
      ...so each new target is a maximum +-(100% DIV (CT_CalcNewTargetBlocksAverage DIV 2)) of
      previous target. This makes target more stable.
    }
    tsTeorical := vteorical;
    tsReal := vreal;
    factor1000 := (((tsTeorical - tsReal) * 1000) DIV (tsTeorical)) * (-1);

    { Important: Note that a -500 is the same that divide by 2 (-100%), and
      1000 is the same that multiply by 2 (+100%), so we limit increase
      in a limit [-500..+1000] for a complete (CT_CalcNewTargetBlocksAverage DIV 2) round }
    if CT_CalcNewTargetBlocksAverage > 1 then
    begin
        factor1000Min := (-500) DIV (CT_CalcNewTargetBlocksAverage DIV 2);
        factor1000Max := (1000) DIV (CT_CalcNewTargetBlocksAverage DIV 2);
    end
    else
    begin
        factor1000Min := (-500);
        factor1000Max := (1000);
    end;

    if factor1000 < factor1000Min then
        factor1000 := factor1000Min
    else if factor1000 > factor1000Max then
        factor1000 := factor1000Max
    else if factor1000 = 0 then
    begin
        Result := actualTarget;
        exit;
    end;

    // Calc new target by increasing factor (-500 <= x <= 1000)
    bn := TBigNum.Create(factor1000);
    bnact := TBigNum.Create(0);
    try
        bnact.RawValue := actualTarget;
        bnaux := bnact.Copy;
        try
            bnact.Multiply(factor1000).Divide(1000).Add(bnaux);
        finally
            bnaux.Free;
        end;
        // Adjust to TargetCompact limitations:
        Result := TargetFromCompact(TargetToCompact(bnact.RawValue));
    finally
        bn.Free;
        bnact.Free;
    end;
end;

class procedure TPascalCoinProtocol.CalcProofOfWork_Part1(const operationBlock: TOperationBlock; var Part1: TRawBytes);
var
    ms: TMemoryStream;
    s: AnsiString;
begin
    ms := TMemoryStream.Create;
    try
        // Part 1
        ms.Write(operationBlock.block, Sizeof(operationBlock.block)); // Little endian
        s := TAccountComp.AccountKey2RawString(operationBlock.account_key);
        ms.WriteBuffer(s[1], length(s));
        ms.Write(operationBlock.reward, Sizeof(operationBlock.reward)); // Little endian
        ms.Write(operationBlock.protocol_version, Sizeof(operationBlock.protocol_version)); // Little endian
        ms.Write(operationBlock.protocol_available, Sizeof(operationBlock.protocol_available)); // Little endian
        ms.Write(operationBlock.compact_target, Sizeof(operationBlock.compact_target)); // Little endian
        SetLength(Part1, ms.Size);
        ms.Position := 0;
        ms.Read(Part1[1], ms.Size);
    finally
        ms.Free;
    end;
end;

class procedure TPascalCoinProtocol.CalcProofOfWork_Part3(const operationBlock: TOperationBlock; var Part3: TRawBytes);
var
    ms: TMemoryStream;
begin
    ms := TMemoryStream.Create;
    try
        ms.WriteBuffer(operationBlock.initial_safe_box_hash[1], length(operationBlock.initial_safe_box_hash));
        ms.WriteBuffer(operationBlock.operations_hash[1], length(operationBlock.operations_hash));
        // Note about fee: Fee is stored in 8 bytes, but only digest first 4 low bytes
        ms.Write(operationBlock.fee, 4);
        SetLength(Part3, ms.Size);
        ms.Position := 0;
        ms.ReadBuffer(Part3[1], ms.Size);
    finally
        ms.Free;
    end;
end;

class procedure TPascalCoinProtocol.CalcProofOfWork(const operationBlock: TOperationBlock; var PoW: TRawBytes);
var
    ms: TMemoryStream;
    s: AnsiString;
begin
    ms := TMemoryStream.Create;
    try
        // Part 1
        ms.Write(operationBlock.block, Sizeof(operationBlock.block)); // Little endian
        s := TAccountComp.AccountKey2RawString(operationBlock.account_key);
        ms.WriteBuffer(s[1], length(s));
        ms.Write(operationBlock.reward, Sizeof(operationBlock.reward)); // Little endian
        ms.Write(operationBlock.protocol_version, Sizeof(operationBlock.protocol_version)); // Little endian
        ms.Write(operationBlock.protocol_available, Sizeof(operationBlock.protocol_available)); // Little endian
        ms.Write(operationBlock.compact_target, Sizeof(operationBlock.compact_target)); // Little endian
        // Part 2
        ms.WriteBuffer(operationBlock.block_payload[1], length(operationBlock.block_payload));
        // Part 3
        ms.WriteBuffer(operationBlock.initial_safe_box_hash[1], length(operationBlock.initial_safe_box_hash));
        ms.WriteBuffer(operationBlock.operations_hash[1], length(operationBlock.operations_hash));
        // Note about fee: Fee is stored in 8 bytes (Int64), but only digest first 4 low bytes
        ms.Write(operationBlock.fee, 4);
        ms.Write(operationBlock.timestamp, 4);
        ms.Write(operationBlock.nonce, 4);
        TCrypto.DoDoubleSha256(ms.Memory, ms.Size, PoW);
    finally
        ms.Free;
    end;
end;

class function TPascalCoinProtocol.GetRewardForNewLine(line_index: Cardinal): UInt64;
Var
    n, i: Cardinal;
begin
    n := (line_index + 1) DIV CT_NewLineRewardDecrease;
    Result := CT_FirstReward;
    for i := 1 to n do
    begin
        Result := Result DIV 2;
    end;
    if (Result < CT_MinReward) then
        Result := CT_MinReward;
end;

class function TPascalCoinProtocol.TargetFromCompact(encoded: Cardinal): TRawBytes;
Var
    nbits, high, offset, i: Cardinal;
    bn: TBigNum;
    raw: TRawBytes;
begin
    {
      Compact Target is a 4 byte value that tells how many "0" must have the hash at left if presented in binay format.
      First byte indicates haw many "0 bits" are on left, so can be from 0x00 to 0xE7
      (Because 24 bits are reserved for 3 bytes, and 1 bit is implicit, max: 256-24-1=231=0xE7)
      Next 3 bytes indicates next value in XOR, stored in RAW format

      Example: If we want a hash lower than 0x0000 0000 0000 65A0 A2F4 +29 bytes
      Binary "0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0110 0101 1010 0000 1010 0010 1111 0100"
      That is 49 zeros on left before first 1. So first byte is 49 decimal = 0x31
      After we have "110 0101 1010 0000 1010 0010 1111 0100 1111 0100" but we only can accept first 3 bytes,
      also note that first "1" is implicit, so value is transformed in
      binary as "10 0101 1010 0000 1010 0010 11" that is 0x96828B
      But note that we must XOR this value, so result offset is: 0x697D74
      Compacted value is: 0x31697D74

      When translate compact target back to target: ( 0x31697D74 )
      0x31 = 49 bits at "0", then 1 bit at "1" followed by XOR 0x697D74 = 0x96828B
      49 "0" bits "0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0"
      0x96828B "1001 0110 1000 0010 1000 1011"
      Hash target = "0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0110 0101 1010 0000 1010 0010 11.. ...."
      Fill last "." with "1"
      Hash target = "0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0110 0101 1010 0000 1010 0010 1111 1111"
      Hash target = 0x00 00 00 00 00 00 65 A0 A2 FF + 29 bytes
      Note that is not exactly the same than expected due to compacted format
    }
    nbits := encoded shr 24;
    i := CT_MinCompactTarget shr 24;
    if nbits < i then
        nbits := i; // min nbits
    if nbits > 231 then
        nbits := 231; // max nbits

    offset := (encoded shl 8) shr 8;
    // Make a XOR at offset and put a "1" on the left
    offset := ((offset XOR $00FFFFFF) OR ($01000000));

    bn := TBigNum.Create(offset);
    Try
        bn.LShift(256 - nbits - 25);
        raw := bn.RawValue;
        SetLength(Result, 32);
        FillChar(Result[1], 32, 0);
        for i := 1 to length(raw) do
        begin
            Result[i + 32 - length(raw)] := raw[i];
        end;
    Finally
        bn.Free;
    End;
end;

class function TPascalCoinProtocol.TargetToCompact(target: TRawBytes): Cardinal;
Var
    bn, bn2: TBigNum;
    i: Int64;
    nbits: Cardinal;
    c: AnsiChar;
    raw: TRawBytes;
    j: Integer;
begin
    { See instructions in explanation of TargetFromCompact }
    Result := 0;
    if length(target) > 32 then
    begin
        raise Exception.Create('Invalid target to compact: ' + TCrypto.ToHexaString(target) + ' (' + inttostr(length(target)) + ')');
    end;
    SetLength(raw, 32);
    FillChar(raw[1], 32, 0);
    for j := 1 to length(target) do
    begin
        raw[j + 32 - length(target)] := target[j];
    end;
    target := raw;

    bn := TBigNum.Create(0);
    bn2 := TBigNum.Create('8000000000000000000000000000000000000000000000000000000000000000'); // First bit 1 followed by 0
    try
        bn.RawValue := target;
        nbits := 0;
        while (bn.CompareTo(bn2) < 0) And (nbits < 231) do
        begin
            bn2.RShift(1);
            inc(nbits);
        end;
        i := CT_MinCompactTarget shr 24;
        if (nbits < i) then
        begin
            Result := CT_MinCompactTarget;
            exit;
        end;
        bn.RShift((256 - 25) - nbits);
        Result := (nbits shl 24) + ((bn.Value AND $00FFFFFF) XOR $00FFFFFF);
    finally
        bn.Free;
        bn2.Free;
    end;
end;

{ TStreamOp }

class function TStreamOp.ReadAccountKey(stream: TStream; var Value: TAccountKey): Integer;
begin
    if stream.Size - stream.Position < 2 then
    begin
        Value := CT_TECDSA_Public_Nul;
        Result := -1;
        exit;
    end;
    stream.Read(Value.EC_OpenSSL_NID, Sizeof(Value.EC_OpenSSL_NID));
    if (ReadAnsiString(stream, Value.x) <= 0) then
    begin
        Value := CT_TECDSA_Public_Nul;
        exit;
    end;
    if (ReadAnsiString(stream, Value.y) <= 0) then
    begin
        Value := CT_TECDSA_Public_Nul;
        exit;
    end;
    Result := Value.EC_OpenSSL_NID;
end;

class function TStreamOp.ReadAnsiString(stream: TStream; var Value: AnsiString): Integer;
Var
    l: Word;
begin
    if stream.Size - stream.Position < 2 then
    begin
        Value := '';
        Result := -1;
        exit;
    end;
    stream.Read(l, 2);
    if stream.Size - stream.Position < l then
    begin
        stream.Position := stream.Position - 2; // Go back!
        Value := '';
        Result := -1;
        exit;
    end;
    SetLength(Value, l);
    stream.ReadBuffer(Value[1], l);
    Result := l + 2;
end;

class function TStreamOp.WriteAccountKey(stream: TStream; const Value: TAccountKey): Integer;
begin
    Result := stream.Write(Value.EC_OpenSSL_NID, Sizeof(Value.EC_OpenSSL_NID));
    Result := Result + WriteAnsiString(stream, Value.x);
    Result := Result + WriteAnsiString(stream, Value.y);
end;

class function TStreamOp.WriteAnsiString(stream: TStream; const Value: AnsiString): Integer;
Var
    l: Word;
begin
    if (length(Value) > (256 * 256)) then
    begin
        TLog.NewLog(lterror, Classname, 'Invalid stream size! ' + inttostr(length(Value)));
        raise Exception.Create('Invalid stream size! ' + inttostr(length(Value)));
    end;

    l := length(Value);
    stream.Write(l, 2);
    if (l > 0) then
        stream.WriteBuffer(Value[1], length(Value));
    Result := l + 2;
end;

{ TAccountComp }
Const
    CT_Base58: AnsiString = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

class function TAccountComp.AccountBlock(const account_number: Cardinal): Cardinal;
begin
    Result := account_number DIV CT_AccountsPerBlock;
end;

class function TAccountComp.AccountInfo2RawString(const accountInfo: TAccountInfo): TRawBytes;
begin
    AccountInfo2RawString(accountInfo, Result);
end;

class procedure TAccountComp.AccountInfo2RawString(const accountInfo: TAccountInfo; var dest: TRawBytes);
Var
    ms: TMemoryStream;
    w: Word;
begin
    case accountInfo.state of
        as_Normal:
            AccountKey2RawString(accountInfo.accountKey, dest);
        as_ForSale:
            begin
                ms := TMemoryStream.Create;
                Try
                    w := CT_AccountInfo_ForSale;
                    ms.Write(w, Sizeof(w));
                    //
                    TStreamOp.WriteAccountKey(ms, accountInfo.accountKey);
                    ms.Write(accountInfo.locked_until_block, Sizeof(accountInfo.locked_until_block));
                    ms.Write(accountInfo.price, Sizeof(accountInfo.price));
                    ms.Write(accountInfo.account_to_pay, Sizeof(accountInfo.account_to_pay));
                    TStreamOp.WriteAccountKey(ms, accountInfo.new_publicKey);
                    SetLength(dest, ms.Size);
                    ms.Position := 0;
                    ms.Read(dest[1], ms.Size);
                Finally
                    ms.Free;
                end;
            end;
    else
        raise Exception.Create('DEVELOP ERROR 20170214-1');
    end;
end;

class function TAccountComp.AccountKey2RawString(const account: TAccountKey): TRawBytes;
begin
    AccountKey2RawString(account, Result);
end;

class procedure TAccountComp.AccountKey2RawString(const account: TAccountKey; var dest: TRawBytes);
Var
    s: TMemoryStream;
begin
    s := TMemoryStream.Create;
    try
        TStreamOp.WriteAccountKey(s, account);
        SetLength(dest, s.Size);
        s.Position := 0;
        s.Read(dest[1], s.Size);
    finally
        s.Free;
    end;
end;

class function TAccountComp.AccountKeyFromImport(const HumanReadable: AnsiString; var account: TAccountKey; var errors: AnsiString): Boolean;
Var
    raw: TRawBytes;
    bn, bnaux, BNBase: TBigNum;
    i, j: Integer;
    s1, s2: AnsiString;
    i64: Int64;
    b: Byte;
begin
    Result := false;
    errors := 'Invalid length';
    account := CT_TECDSA_Public_Nul;
    if length(HumanReadable) < 20 then
        exit;
    bn := TBigNum.Create(0);
    bnaux := TBigNum.Create;
    BNBase := TBigNum.Create(1);
    try
        for i := length(HumanReadable) downto 1 do
        begin
            if (HumanReadable[i] <> ' ') then
            begin
                j := pos(HumanReadable[i], CT_Base58);
                if j = 0 then
                begin
                    errors := 'Invalid char "' + HumanReadable[i] + '" at pos ' + inttostr(i) + '/' + inttostr(length(HumanReadable));
                    exit;
                end;
                bnaux.Value := j - 1;
                bnaux.Multiply(BNBase);
                bn.Add(bnaux);
                BNBase.Multiply(length(CT_Base58));
            end;
        end;
        // Last 8 hexa chars are the checksum of others
        s1 := Copy(bn.HexaValue, 3, length(bn.HexaValue));
        s2 := Copy(s1, length(s1) - 7, 8);
        s1 := Copy(s1, 1, length(s1) - 8);
        raw := TCrypto.HexaToRaw(s1);
        s1 := TCrypto.ToHexaString(TCrypto.DoSha256(raw));
        if Copy(s1, 1, 8) <> s2 then
        begin
            // Invalid checksum
            errors := 'Invalid checksum';
            exit;
        end;
        try
            account := TAccountComp.RawString2Accountkey(raw);
            Result := true;
            errors := '';
        except
            // Nothing to do... invalid
            errors := 'Error on conversion from Raw to Account key';
        end;
    Finally
        bn.Free;
        BNBase.Free;
        bnaux.Free;
    end;
end;

class function TAccountComp.AccountNumberToAccountTxtNumber(account_number: Cardinal): AnsiString;
Var
    an: Int64;
begin
    an := account_number; // Converting to int64 to prevent overflow when *101
    an := ((an * 101) MOD 89) + 10;
    Result := inttostr(account_number) + '-' + inttostr(an);
end;

class function TAccountComp.AccountPublicKeyExport(const account: TAccountKey): AnsiString;
Var
    raw: TRawBytes;
    bn, BNMod, BNDiv: TBigNum;
    i: Integer;
begin
    Result := '';
    raw := AccountKey2RawString(account);
    bn := TBigNum.Create;
    BNMod := TBigNum.Create;
    BNDiv := TBigNum.Create(length(CT_Base58));
    try
        bn.HexaValue := '01' + TCrypto.ToHexaString(raw) + TCrypto.ToHexaString(Copy(TCrypto.DoSha256(raw), 1, 4));
        while (Not bn.IsZero) do
        begin
            bn.Divide(BNDiv, BNMod);
            If (BNMod.Value >= 0) And (BNMod.Value < length(CT_Base58)) then
                Result := CT_Base58[Byte(BNMod.Value) + 1] + Result
            else
                raise Exception.Create('Error converting to Base 58');
        end;
    finally
        bn.Free;
        BNMod.Free;
        BNDiv.Free;
    end;
end;

class function TAccountComp.AccountPublicKeyImport(const HumanReadable: AnsiString; var account: TAccountKey; var errors: AnsiString): Boolean;
Var
    raw: TRawBytes;
    bn, bnaux, BNBase: TBigNum;
    i, j: Integer;
    s1, s2: AnsiString;
    i64: Int64;
    b: Byte;
begin
    Result := false;
    errors := 'Invalid length';
    account := CT_TECDSA_Public_Nul;
    if length(HumanReadable) < 20 then
        exit;
    bn := TBigNum.Create(0);
    bnaux := TBigNum.Create;
    BNBase := TBigNum.Create(1);
    try
        for i := length(HumanReadable) downto 1 do
        begin
            j := pos(HumanReadable[i], CT_Base58);
            if j = 0 then
            begin
                errors := 'Invalid char "' + HumanReadable[i] + '" at pos ' + inttostr(i) + '/' + inttostr(length(HumanReadable));
                exit;
            end;
            bnaux.Value := j - 1;
            bnaux.Multiply(BNBase);
            bn.Add(bnaux);
            BNBase.Multiply(length(CT_Base58));
        end;
        // Last 8 hexa chars are the checksum of others
        s1 := Copy(bn.HexaValue, 3, length(bn.HexaValue));
        s2 := Copy(s1, length(s1) - 7, 8);
        s1 := Copy(s1, 1, length(s1) - 8);
        raw := TCrypto.HexaToRaw(s1);
        s1 := TCrypto.ToHexaString(TCrypto.DoSha256(raw));
        if Copy(s1, 1, 8) <> s2 then
        begin
            // Invalid checksum
            errors := 'Invalid checksum';
            exit;
        end;
        try
            account := TAccountComp.RawString2Accountkey(raw);
            Result := true;
            errors := '';
        except
            // Nothing to do... invalid
            errors := 'Error on conversion from Raw to Account key';
        end;
    Finally
        bn.Free;
        BNBase.Free;
        bnaux.Free;
    end;
end;

class function TAccountComp.AccountTxtNumberToAccountNumber(const account_txt_number: AnsiString; var account_number: Cardinal): Boolean;
Var
    i: Integer;
    char1: AnsiChar;
    char2: AnsiChar;
    an, rn, anaux: Int64;
begin
    Result := false;
    if length(trim(account_txt_number)) = 0 then
        exit;
    an := 0;
    i := 1;
    while (i <= length(account_txt_number)) do
    begin
        if account_txt_number[i] in ['0' .. '9'] then
        begin
            an := (an * 10) + ord(account_txt_number[i]) - ord('0');
        end
        else
        begin
            break;
        end;
        inc(i);
    end;
    account_number := an;
    if (i > length(account_txt_number)) then
    begin
        Result := true;
        exit;
    end;
    if (account_txt_number[i] in ['-', '.', ' ']) then
        inc(i);
    if length(account_txt_number) - 1 <> i then
        exit;
    rn := StrToIntDef(Copy(account_txt_number, i, length(account_txt_number)), 0);
    anaux := ((an * 101) MOD 89) + 10;
    Result := rn = anaux;
end;

class function TAccountComp.EqualAccountInfos(const accountInfo1, accountInfo2: TAccountInfo): Boolean;
begin
    Result := (accountInfo1.state = accountInfo2.state) And (EqualAccountKeys(accountInfo1.accountKey, accountInfo2.accountKey)) And
      (accountInfo1.locked_until_block = accountInfo2.locked_until_block) And (accountInfo1.price = accountInfo2.price) And
      (accountInfo1.account_to_pay = accountInfo2.account_to_pay) and (EqualAccountKeys(accountInfo1.new_publicKey, accountInfo2.new_publicKey));
end;

class function TAccountComp.EqualAccountKeys(const account1, account2: TAccountKey): Boolean;
begin
    Result := (account1.EC_OpenSSL_NID = account2.EC_OpenSSL_NID) And (account1.x = account2.x) And (account1.y = account2.y);
end;

class function TAccountComp.FormatMoney(Money: Int64): AnsiString;
begin
    Result := FormatFloat('#,###0.0000', (Money / 10000));
end;

class function TAccountComp.GetECInfoTxt(const EC_OpenSSL_NID: Word): AnsiString;
begin
    case EC_OpenSSL_NID of
        CT_NID_secp256k1:
            begin
                Result := 'secp256k1';
            end;
        CT_NID_secp384r1:
            begin
                Result := 'secp384r1';
            end;
        CT_NID_sect283k1:
            Begin
                Result := 'secp283k1';
            End;
        CT_NID_secp521r1:
            begin
                Result := 'secp521r1';
            end
    else
        Result := '(Unknown ID:' + inttostr(EC_OpenSSL_NID) + ')';
    end;
end;

class function TAccountComp.IsAccountBlockedByProtocol(account_number, blocks_count: Cardinal): Boolean;
begin
    if blocks_count < CT_WaitNewBlocksBeforeTransaction then
        Result := true
    else
    begin
        Result := ((blocks_count - CT_WaitNewBlocksBeforeTransaction) * CT_AccountsPerBlock) <= account_number;
    end;
end;

class function TAccountComp.IsAccountForSale(const accountInfo: TAccountInfo): Boolean;
begin
    Result := (accountInfo.state = as_ForSale);
end;

class function TAccountComp.IsAccountForSaleAcceptingTransactions(const accountInfo: TAccountInfo): Boolean;
var
    errors: AnsiString;
begin
    Result := (accountInfo.state = as_ForSale) And (IsValidAccountKey(accountInfo.new_publicKey, errors));
end;

class function TAccountComp.IsAccountLocked(const accountInfo: TAccountInfo; blocks_count: Cardinal): Boolean;
begin
    Result := (accountInfo.state = as_ForSale) And ((accountInfo.locked_until_block) >= blocks_count);
end;

class procedure TAccountComp.SaveTOperationBlockToStream(const stream: TStream; const operationBlock: TOperationBlock);
begin
    stream.Write(operationBlock.block, Sizeof(operationBlock.block));
    TStreamOp.WriteAccountKey(stream, operationBlock.account_key);
    stream.Write(operationBlock.reward, Sizeof(operationBlock.reward));
    stream.Write(operationBlock.fee, Sizeof(operationBlock.fee));
    stream.Write(operationBlock.protocol_version, Sizeof(operationBlock.protocol_version));
    stream.Write(operationBlock.protocol_available, Sizeof(operationBlock.protocol_available));
    stream.Write(operationBlock.timestamp, Sizeof(operationBlock.timestamp));
    stream.Write(operationBlock.compact_target, Sizeof(operationBlock.compact_target));
    stream.Write(operationBlock.nonce, Sizeof(operationBlock.nonce));
    TStreamOp.WriteAnsiString(stream, operationBlock.block_payload);
    TStreamOp.WriteAnsiString(stream, operationBlock.initial_safe_box_hash);
    TStreamOp.WriteAnsiString(stream, operationBlock.operations_hash);
    TStreamOp.WriteAnsiString(stream, operationBlock.proof_of_work);
end;

class function TAccountComp.LoadTOperationBlockFromStream(const stream: TStream; var operationBlock: TOperationBlock): Boolean;
begin
    Result := false;
    operationBlock := CT_OperationBlock_NUL;
    If stream.Read(operationBlock.block, Sizeof(operationBlock.block)) < Sizeof(operationBlock.block) then
        exit;
    TStreamOp.ReadAccountKey(stream, operationBlock.account_key);
    stream.Read(operationBlock.reward, Sizeof(operationBlock.reward));
    stream.Read(operationBlock.fee, Sizeof(operationBlock.fee));
    stream.Read(operationBlock.protocol_version, Sizeof(operationBlock.protocol_version));
    stream.Read(operationBlock.protocol_available, Sizeof(operationBlock.protocol_available));
    stream.Read(operationBlock.timestamp, Sizeof(operationBlock.timestamp));
    stream.Read(operationBlock.compact_target, Sizeof(operationBlock.compact_target));
    stream.Read(operationBlock.nonce, Sizeof(operationBlock.nonce));
    if TStreamOp.ReadAnsiString(stream, operationBlock.block_payload) < 0 then
        exit;
    if TStreamOp.ReadAnsiString(stream, operationBlock.initial_safe_box_hash) < 0 then
        exit;
    if TStreamOp.ReadAnsiString(stream, operationBlock.operations_hash) < 0 then
        exit;
    if TStreamOp.ReadAnsiString(stream, operationBlock.proof_of_work) < 0 then
        exit;
    Result := true;
end;

class function TAccountComp.IsValidAccountInfo(const accountInfo: TAccountInfo; var errors: AnsiString): Boolean;
Var
    s: AnsiString;
begin
    errors := '';
    case accountInfo.state of
        as_Unknown:
            begin
                errors := 'Account state is unknown';
                Result := false;
            end;
        as_Normal:
            begin
                Result := IsValidAccountKey(accountInfo.accountKey, errors);
            end;
        as_ForSale:
            begin
                If Not IsValidAccountKey(accountInfo.accountKey, s) then
                    errors := errors + ' ' + s;
                Result := errors = '';
            end;
    else
        raise Exception.Create('DEVELOP ERROR 20170214-3');
    end;
end;

class function TAccountComp.IsValidAccountKey(const account: TAccountKey; var errors: AnsiString): Boolean;
begin
    errors := '';
    case account.EC_OpenSSL_NID of
        CT_NID_secp256k1, CT_NID_secp384r1, CT_NID_sect283k1, CT_NID_secp521r1:
            begin
                Result := TECPrivateKey.IsValidPublicKey(account);
                if Not Result then
                begin
                    errors := Format('Invalid AccountKey type:%d - Length x:%d y:%d Error:%s', [account.EC_OpenSSL_NID, length(account.x), length(account.y),
                      ERR_error_string(ERR_get_error(), nil)]);
                end;
            end;
    else
        errors := Format('Invalid AccountKey type:%d (Unknown type) - Length x:%d y:%d', [account.EC_OpenSSL_NID, length(account.x), length(account.y)]);
        Result := false;
    end;
    if (errors = '') And (Not Result) then
        errors := ERR_error_string(ERR_get_error(), nil);
end;

class function TAccountComp.PrivateToAccountkey(key: TECPrivateKey): TAccountKey;
begin
    Result := key.PublicKey;
end;

class function TAccountComp.RawString2AccountInfo(const rawaccstr: TRawBytes): TAccountInfo;
begin
    RawString2AccountInfo(rawaccstr, Result);
end;

class procedure TAccountComp.RawString2AccountInfo(const rawaccstr: TRawBytes; var dest: TAccountInfo);
Var
    ms: TMemoryStream;
    w: Word;
begin
    if length(rawaccstr) = 0 then
    begin
        dest := CT_AccountInfo_NUL;
        exit;
    end;
    ms := TMemoryStream.Create;
    Try
        ms.WriteBuffer(rawaccstr[1], length(rawaccstr));
        ms.Position := 0;
        If ms.Read(w, Sizeof(w)) <> Sizeof(w) then
            exit;
        case w of
            CT_NID_secp256k1, CT_NID_secp384r1, CT_NID_sect283k1, CT_NID_secp521r1:
                Begin
                    dest.state := as_Normal;
                    RawString2Accountkey(rawaccstr, dest.accountKey);
                    dest.locked_until_block := CT_AccountInfo_NUL.locked_until_block;
                    dest.price := CT_AccountInfo_NUL.price;
                    dest.account_to_pay := CT_AccountInfo_NUL.account_to_pay;
                    dest.new_publicKey := CT_AccountInfo_NUL.new_publicKey;
                End;
            CT_AccountInfo_ForSale:
                Begin
                    TStreamOp.ReadAccountKey(ms, dest.accountKey);
                    ms.Read(dest.locked_until_block, Sizeof(dest.locked_until_block));
                    ms.Read(dest.price, Sizeof(dest.price));
                    ms.Read(dest.account_to_pay, Sizeof(dest.account_to_pay));
                    TStreamOp.ReadAccountKey(ms, dest.new_publicKey);
                    dest.state := as_ForSale;
                End;
        else
            raise Exception.Create('DEVELOP ERROR 20170214-2');
        end;
    Finally
        ms.Free;
    end;
end;

class function TAccountComp.RawString2Accountkey(const rawaccstr: TRawBytes): TAccountKey;
begin
    RawString2Accountkey(rawaccstr, Result);
end;

class procedure TAccountComp.RawString2Accountkey(const rawaccstr: TRawBytes; var dest: TAccountKey);
Var
    ms: TMemoryStream;
begin
    if length(rawaccstr) = 0 then
    begin
        dest := CT_TECDSA_Public_Nul;
        exit;
    end;
    ms := TMemoryStream.Create;
    try
        ms.WriteBuffer(rawaccstr[1], length(rawaccstr));
        ms.Position := 0;
        TStreamOp.ReadAccountKey(ms, dest);
    finally
        ms.Free;
    end;
end;

class function TAccountComp.TxtToMoney(const moneytxt: AnsiString; var Money: Int64): Boolean;
Var
    s: AnsiString;
    i: Integer;
    DecimalSep, ThousandSep: Char;
begin
    Money := 0;
    if trim(moneytxt) = '' then
    begin
        Result := true;
        exit;
    end;
    try
{$IFDEF FPC}
        DecimalSep := DecimalSeparator;
        ThousandSep := ThousandSeparator;
{$ELSE}
        DecimalSep := FormatSettings.DecimalSeparator;
        ThousandSep := FormatSettings.ThousandSeparator;
{$ENDIF}

        If pos(FormatSettings.DecimalSeparator, moneytxt) <= 0 then
        begin
            // No decimal separator, consider ThousandSeparator as a decimal separator
            s := StringReplace(moneytxt, ThousandSep, DecimalSep, [rfReplaceAll]);
        end
        else
        begin
            s := StringReplace(moneytxt, ThousandSep, '', [rfReplaceAll]);
        end;
        Money := Round(StrToFloat(s) * 10000);
        Result := true;
    Except
        Result := false;
    end;
end;

class procedure TAccountComp.ValidsEC_OpenSSL_NID(list: TList);
begin
    list.Clear;
    list.Add(TObject(CT_NID_secp256k1)); // = 714
    list.Add(TObject(CT_NID_secp384r1)); // = 715
    list.Add(TObject(CT_NID_sect283k1)); // = 729
    list.Add(TObject(CT_NID_secp521r1)); // = 716
end;

{ TPCSafeBox }

// New on version 2: To reduce mem usage
{$DEFINE uselowmem}
{$IFDEF uselowmem}

Type
    { In order to store less memory on RAM, those types will be used
      to store in RAM memory (better than to use original ones)
      This will reduce 10-15% of memory usage.
      For future versions, will be a good solution to use those instead
      of originals, but }
    TMemAccount = Record // TAccount with less memory usage
        // account number is discarded (-4 bytes)
        accountInfo: TDynRawBytes;
        balance: UInt64;
        updated_block: Cardinal;
        n_operation: Cardinal;
        name: TRawBytes;
        account_type: Word;
        previous_updated_block: Cardinal;
    End;

    TMemOperationBlock = Record // TOperationBlock with less memory usage
        // block number is discarded (-4 bytes)
        account_key: TDynRawBytes;
        reward: UInt64;
        fee: UInt64;
        protocol_version: Word;
        protocol_available: Word;
        timestamp: Cardinal;
        compact_target: Cardinal;
        nonce: Cardinal;
        block_payload: TDynRawBytes;
        initial_safe_box_hash: T32Bytes; // 32 direct bytes instead of use an AnsiString (-8 bytes)
        operations_hash: T32Bytes; // 32 direct bytes instead of use an AnsiString (-8 bytes)
        proof_of_work: T32Bytes; // 32 direct bytes instead of use an AnsiString (-8 bytes)
    end;

    TMemBlockAccount = Record // TBlockAccount with less memory usage
        blockchainInfo: TMemOperationBlock;
        accounts: Array [0 .. CT_AccountsPerBlock - 1] of TMemAccount;
        block_hash: T32Bytes; // 32 direct bytes instead of use an AnsiString (-8 bytes)
        accumulatedWork: UInt64;
    end;

Type
    PBlockAccount = ^TMemBlockAccount;
{$ELSE}

Type
    PBlockAccount = ^TBlockAccount;
    TMemAccount = TAccount;
    TMemBlockAccount = TBlockAccount;
{$ENDIF}

procedure ToTMemAccount(Const Source: TAccount; var dest: TMemAccount);
{$IFDEF uselowmem}
Var
    raw: TRawBytes;
{$ENDIF}
begin
{$IFDEF uselowmem}
    TAccountComp.AccountInfo2RawString(Source.accountInfo, raw);
    TBaseType.To256RawBytes(raw, dest.accountInfo);
    dest.balance := Source.balance;
    dest.updated_block := Source.updated_block;
    dest.n_operation := Source.n_operation;
    dest.name := Source.name;
    dest.account_type := Source.account_type;
    dest.previous_updated_block := Source.previous_updated_block;
{$ELSE}
    dest := Source;
{$ENDIF}
end;

procedure ToTAccount(const Source: TMemAccount; account_number: Cardinal; var dest: TAccount);
{$IFDEF uselowmem}
var
    raw: TRawBytes;
{$ENDIF}
begin
{$IFDEF uselowmem}
    dest.account := account_number;
    TBaseType.ToRawBytes(Source.accountInfo, raw);
    TAccountComp.RawString2AccountInfo(raw, dest.accountInfo);
    dest.balance := Source.balance;
    dest.updated_block := Source.updated_block;
    dest.n_operation := Source.n_operation;
    dest.name := Source.name;
    dest.account_type := Source.account_type;
    dest.previous_updated_block := Source.previous_updated_block;
{$ELSE}
    dest := Source;
{$ENDIF}
end;

procedure ToTMemBlockAccount(const Source: TBlockAccount; var dest: TMemBlockAccount);
{$IFDEF uselowmem}
var
    i: Integer;
var
    raw: TRawBytes;
{$ENDIF}
Begin
{$IFDEF uselowmem}
    TAccountComp.AccountKey2RawString(Source.blockchainInfo.account_key, raw);
    TBaseType.To256RawBytes(raw, dest.blockchainInfo.account_key);
    dest.blockchainInfo.reward := Source.blockchainInfo.reward;
    dest.blockchainInfo.fee := Source.blockchainInfo.fee;
    dest.blockchainInfo.protocol_version := Source.blockchainInfo.protocol_version;
    dest.blockchainInfo.protocol_available := Source.blockchainInfo.protocol_available;
    dest.blockchainInfo.timestamp := Source.blockchainInfo.timestamp;
    dest.blockchainInfo.compact_target := Source.blockchainInfo.compact_target;
    dest.blockchainInfo.nonce := Source.blockchainInfo.nonce;
    TBaseType.To256RawBytes(Source.blockchainInfo.block_payload, dest.blockchainInfo.block_payload);
    TBaseType.To32Bytes(Source.blockchainInfo.initial_safe_box_hash, dest.blockchainInfo.initial_safe_box_hash);
    TBaseType.To32Bytes(Source.blockchainInfo.operations_hash, dest.blockchainInfo.operations_hash);
    TBaseType.To32Bytes(Source.blockchainInfo.proof_of_work, dest.blockchainInfo.proof_of_work);

    for i := Low(Source.accounts) to High(Source.accounts) do
    begin
        ToTMemAccount(Source.accounts[i], dest.accounts[i]);
    end;
    TBaseType.To32Bytes(Source.block_hash, dest.block_hash);
    dest.accumulatedWork := Source.accumulatedWork;
{$ELSE}
    dest := Source;
{$ENDIF}
end;

procedure ToTBlockAccount(const Source: TMemBlockAccount; block_number: Cardinal; var dest: TBlockAccount);
{$IFDEF uselowmem}
var
    i: Integer;
    raw: TRawBytes;
{$ENDIF}
begin
{$IFDEF uselowmem}
    dest.blockchainInfo.block := block_number;
    TBaseType.ToRawBytes(Source.blockchainInfo.account_key, raw);
    TAccountComp.RawString2Accountkey(raw, dest.blockchainInfo.account_key);
    dest.blockchainInfo.reward := Source.blockchainInfo.reward;
    dest.blockchainInfo.fee := Source.blockchainInfo.fee;
    dest.blockchainInfo.protocol_version := Source.blockchainInfo.protocol_version;
    dest.blockchainInfo.protocol_available := Source.blockchainInfo.protocol_available;
    dest.blockchainInfo.timestamp := Source.blockchainInfo.timestamp;
    dest.blockchainInfo.compact_target := Source.blockchainInfo.compact_target;
    dest.blockchainInfo.nonce := Source.blockchainInfo.nonce;
    TBaseType.ToRawBytes(Source.blockchainInfo.block_payload, dest.blockchainInfo.block_payload);
    TBaseType.ToRawBytes(Source.blockchainInfo.initial_safe_box_hash, dest.blockchainInfo.initial_safe_box_hash);
    TBaseType.ToRawBytes(Source.blockchainInfo.operations_hash, dest.blockchainInfo.operations_hash);
    TBaseType.ToRawBytes(Source.blockchainInfo.proof_of_work, dest.blockchainInfo.proof_of_work);

    for i := Low(Source.accounts) to High(Source.accounts) do
    begin
        ToTAccount(Source.accounts[i], (block_number * CT_AccountsPerBlock) + i, dest.accounts[i]);
    end;
    TBaseType.ToRawBytes(Source.block_hash, dest.block_hash);
    dest.accumulatedWork := Source.accumulatedWork;
{$ELSE}
    dest := Source;
{$ENDIF}
end;

function TPCSafeBox.account(account_number: Cardinal): TAccount;
var
    b: Cardinal;
begin
    b := account_number DIV CT_AccountsPerBlock;
    if (b < 0) Or (b >= FBlockAccountsList.Count) then
        raise Exception.Create('Invalid account: ' + inttostr(account_number));
    ToTAccount(PBlockAccount(FBlockAccountsList.Items[b])^.accounts[account_number MOD CT_AccountsPerBlock], account_number, Result);
end;

function TPCSafeBox.AddNew(const blockChain: TOperationBlock): TBlockAccount;
var
    i, base_addr: Integer;
    P: PBlockAccount;
    accs: Array of Cardinal;
begin
    Result := CT_BlockAccount_NUL;
    Result.blockchainInfo := blockChain;
    If blockChain.block <> blocksCount then
        Raise Exception.Create('ERROR DEV 20170427-2');
    If blockChain.fee <> FTotalFee then
        Raise Exception.Create('ERROR DEV 20170427-3');
    base_addr := blocksCount * CT_AccountsPerBlock;
    SetLength(accs, length(Result.accounts));
    for i := Low(Result.accounts) to High(Result.accounts) do
    begin
        Result.accounts[i] := CT_Account_NUL;
        Result.accounts[i].account := base_addr + i;
        Result.accounts[i].accountInfo.state := as_Normal;
        Result.accounts[i].accountInfo.accountKey := blockChain.account_key;
        Result.accounts[i].updated_block := blocksCount;
        Result.accounts[i].n_operation := 0;
        if i = Low(Result.accounts) then
        begin
            // Only first account wins the reward + fee
            Result.accounts[i].balance := blockChain.reward + blockChain.fee;
        end
        else
        begin
        end;
        accs[i] := base_addr + i;
    end;
    inc(FWorkSum, Result.blockchainInfo.compact_target);
    Result.accumulatedWork := FWorkSum;
    // Calc block hash
    Result.block_hash := CalcBlockHash(Result, FCurrentProtocol >= CT_PROTOCOL_2);

    New(P);
    ToTMemBlockAccount(Result, P^);

    FBlockAccountsList.Add(P);
    FBufferBlocksHash := FBufferBlocksHash + Result.block_hash;
    inc(FTotalBalance, blockChain.reward + blockChain.fee);
    Dec(FTotalFee, blockChain.fee);
    AccountKeyListAddAccounts(blockChain.account_key, accs);
    // Calculating new value of safebox
    FSafeBoxHash := CalcSafeBoxHash;
end;

procedure TPCSafeBox.AccountKeyListAddAccounts(const accountKey: TAccountKey; const accounts: array of Cardinal);
Var
    i: Integer;
begin
    for i := 0 to FListOfOrderedAccountKeysList.Count - 1 do
    begin
        TOrderedAccountKeysList(FListOfOrderedAccountKeysList[i]).AddAccounts(accountKey, accounts);
    end;
end;

procedure TPCSafeBox.AccountKeyListRemoveAccount(const accountKey: TAccountKey; const accounts: array of Cardinal);
Var
    i: Integer;
begin
    for i := 0 to FListOfOrderedAccountKeysList.Count - 1 do
    begin
        TOrderedAccountKeysList(FListOfOrderedAccountKeysList[i]).RemoveAccounts(accountKey, accounts);
    end;
end;

function TPCSafeBox.AccountsCount: Integer;
begin
    Result := blocksCount * CT_AccountsPerBlock;
end;

function TPCSafeBox.block(block_number: Cardinal): TBlockAccount;
begin
    if (block_number < 0) Or (block_number >= FBlockAccountsList.Count) then
        raise Exception.Create('Invalid block number: ' + inttostr(block_number));
    ToTBlockAccount(PBlockAccount(FBlockAccountsList.Items[block_number])^, block_number, Result);
end;

class function TPCSafeBox.BlockAccountToText(const block: TBlockAccount): AnsiString;
begin
    Result := Format('Block:%d Timestamp:%d BlockHash:%s', [block.blockchainInfo.block, block.blockchainInfo.timestamp,
      TCrypto.ToHexaString(block.block_hash)]);
end;

function TPCSafeBox.blocksCount: Integer;
begin
    Result := FBlockAccountsList.Count;
end;

class function TPCSafeBox.CalcBlockHash(const block: TBlockAccount; useProtocol2Method: Boolean): TRawBytes;
// Protocol v2 update:
// In order to store values to generate PoW and allow Safebox checkpointing, we
// store info about TOperationBlock on each row and use it to obtain blockchash
Var
    raw: TRawBytes;
    ms: TMemoryStream;
    i: Integer;
begin
    ms := TMemoryStream.Create;
    try
        If (Not useProtocol2Method) then
        begin
            // PROTOCOL 1 BlockHash calculation
            ms.Write(block.blockchainInfo.block, 4); // Little endian
            for i := Low(block.accounts) to High(block.accounts) do
            begin
                ms.Write(block.accounts[i].account, 4); // Little endian
                raw := TAccountComp.AccountInfo2RawString(block.accounts[i].accountInfo);
                ms.WriteBuffer(raw[1], length(raw)); // Raw bytes
                ms.Write(block.accounts[i].balance, Sizeof(UInt64)); // Little endian
                ms.Write(block.accounts[i].updated_block, 4); // Little endian
                ms.Write(block.accounts[i].n_operation, 4); // Little endian
            end;
            ms.Write(block.blockchainInfo.timestamp, 4); // Little endian
        end
        else
        begin
            // PROTOCOL 2 BlockHash calculation
            TAccountComp.SaveTOperationBlockToStream(ms, block.blockchainInfo);
            for i := Low(block.accounts) to High(block.accounts) do
            begin
                ms.Write(block.accounts[i].account, 4); // Little endian
                raw := TAccountComp.AccountInfo2RawString(block.accounts[i].accountInfo);
                ms.WriteBuffer(raw[1], length(raw)); // Raw bytes
                ms.Write(block.accounts[i].balance, Sizeof(UInt64)); // Little endian
                ms.Write(block.accounts[i].updated_block, 4); // Little endian
                ms.Write(block.accounts[i].n_operation, 4); // Little endian
                // Use new Protocol 2 fields
                If length(block.accounts[i].name) > 0 then
                begin
                    ms.WriteBuffer(block.accounts[i].name[1], length(block.accounts[i].name));
                end;
                ms.Write(block.accounts[i].account_type, 2);
            end;
            ms.Write(block.accumulatedWork, Sizeof(block.accumulatedWork));
        end;
        Result := TCrypto.DoSha256(ms.Memory, ms.Size)
    finally
        ms.Free;
    end;
end;

function TPCSafeBox.CalcBlockHashRateInKhs(block_number: Cardinal; Previous_blocks_average: Cardinal): Int64;
Var
    c, t: Cardinal;
    t_sum: Extended;
    bn, bn_sum: TBigNum;
begin
    FLock.Acquire;
    Try
        bn_sum := TBigNum.Create;
        try
            if (block_number = 0) then
            begin
                Result := 1;
                exit;
            end;
            if (block_number < 0) Or (block_number >= FBlockAccountsList.Count) then
                raise Exception.Create('Invalid block number: ' + inttostr(block_number));
            if (Previous_blocks_average <= 0) then
                raise Exception.Create('Dev error 20161016-1');
            if (Previous_blocks_average > block_number) then
                Previous_blocks_average := block_number;
            //
            c := (block_number - Previous_blocks_average) + 1;
            t_sum := 0;
            while (c <= block_number) do
            begin
                bn := TBigNum.TargetToHashRate(PBlockAccount(FBlockAccountsList.Items[c])^.blockchainInfo.compact_target);
                try
                    bn_sum.Add(bn);
                finally
                    bn.Free;
                end;
                t_sum := t_sum + (PBlockAccount(FBlockAccountsList.Items[c])^.blockchainInfo.timestamp - PBlockAccount(FBlockAccountsList.Items[c - 1])
                  ^.blockchainInfo.timestamp);
                inc(c);
            end;
            bn_sum.Divide(Previous_blocks_average); // Obtain target average
            t_sum := t_sum / Previous_blocks_average; // time average
            t := Round(t_sum);
            if (t <> 0) then
            begin
                bn_sum.Divide(t);
            end;
            Result := bn_sum.Divide(1024).Value; // Value in Kh/s
        Finally
            bn_sum.Free;
        end;
    Finally
        FLock.Release;
    End;
end;

function TPCSafeBox.CalcSafeBoxHash: TRawBytes;
begin
    // If No buffer to hash is because it's firts block... so use Genesis: CT_Genesis_Magic_String_For_Old_Block_Hash
    if (FBufferBlocksHash = '') then
        Result := TCrypto.DoSha256(CT_Genesis_Magic_String_For_Old_Block_Hash)
    else
        Result := TCrypto.DoSha256(FBufferBlocksHash);
end;

function TPCSafeBox.CanUpgradeToProtocol2: Boolean;
begin
    Result := (FCurrentProtocol < CT_PROTOCOL_2) and (blocksCount >= CT_Protocol_Upgrade_v2_MinBlock);
end;

procedure TPCSafeBox.CheckMemory;
{ Note about Free Pascal compiler
  When compiling using Delphi it's memory manager more is efficient and does not increase, but
  When compiling using Free Pascal Compiler, is a good solution to "force" generate a new SafeBox
  in order to free memory not used. Tested with FPC 3.0 }
{$IFDEF FPC}
Var
    sb: TPCSafeBox;
    tc: Cardinal;
{$ENDIF}
begin
{$IFDEF FPC}
    StartThreadSafe;
    try
        tc := GetTickCount;
        sb := TPCSafeBox.Create;
        try
            sb.CopyFrom(Self);
            Self.Clear;
            Self.CopyFrom(sb);
        finally
            sb.Free;
        end;
        tc := GetTickCount - tc;
        TLog.NewLog(ltDebug, Classname, 'Checked memory ' + inttostr(tc) + ' miliseonds');
    finally
        EndThreadSave;
    end;
{$ENDIF}
end;

procedure TPCSafeBox.Clear;
Var
    i: Integer;
    P: PBlockAccount;
begin
    StartThreadSafe;
    Try
        for i := 0 to FBlockAccountsList.Count - 1 do
        begin
            P := FBlockAccountsList.Items[i];
            Dispose(P);
        end;
        FOrderedByName.Clear;
        FBlockAccountsList.Clear;
        For i := 0 to FListOfOrderedAccountKeysList.Count - 1 do
        begin
            TOrderedAccountKeysList(FListOfOrderedAccountKeysList[i]).ClearAccounts(false);
        end;
        FBufferBlocksHash := '';
        FTotalBalance := 0;
        FTotalFee := 0;
        FSafeBoxHash := CalcSafeBoxHash;
        FWorkSum := 0;
        FCurrentProtocol := CT_PROTOCOL_1;
    Finally
        EndThreadSave;
    end;
end;

procedure TPCSafeBox.CopyFrom(accounts: TPCSafeBox);
Var
    i, j: Cardinal;
    P: PBlockAccount;
    BA: TBlockAccount;
begin
    StartThreadSafe;
    Try
        accounts.StartThreadSafe;
        try
            if accounts = Self then
                exit;
            Clear;
            if accounts.blocksCount > 0 then
            begin
                FBlockAccountsList.Capacity := accounts.blocksCount;
                for i := 0 to accounts.blocksCount - 1 do
                begin
                    BA := accounts.block(i);
                    New(P);
                    ToTMemBlockAccount(BA, P^);
                    FBlockAccountsList.Add(P);
                    for j := Low(BA.accounts) to High(BA.accounts) do
                    begin
                        If (BA.accounts[j].name <> '') then
                            FOrderedByName.Add(BA.accounts[j].name, BA.accounts[j].account);
                        AccountKeyListAddAccounts(BA.accounts[j].accountInfo.accountKey, [BA.accounts[j].account]);
                    end;
                end;
            end;
            FTotalBalance := accounts.TotalBalance;
            FTotalFee := accounts.FTotalFee;
            FBufferBlocksHash := accounts.FBufferBlocksHash;
            FSafeBoxHash := accounts.FSafeBoxHash;
            FWorkSum := accounts.FWorkSum;
            FCurrentProtocol := accounts.FCurrentProtocol;
        finally
            accounts.EndThreadSave;
        end;
    finally
        EndThreadSave;
    end;
end;

constructor TPCSafeBox.Create;
begin
    FLock := TPCCriticalSection.Create('TPCSafeBox_Lock');
    FBlockAccountsList := TList.Create;
    FListOfOrderedAccountKeysList := TList.Create;
    FCurrentProtocol := CT_PROTOCOL_1;
    FOrderedByName := TOrderedRawList.Create;
    Clear;
end;

destructor TPCSafeBox.Destroy;
Var
    i: Integer;
begin
    Clear;
    for i := 0 to FListOfOrderedAccountKeysList.Count - 1 do
    begin
        TOrderedAccountKeysList(FListOfOrderedAccountKeysList[i]).FAccountList := Nil;
    end;
    FreeAndNil(FBlockAccountsList);
    FreeAndNil(FListOfOrderedAccountKeysList);
    FreeAndNil(FLock);
    FreeAndNil(FOrderedByName);
    inherited;
end;

function TPCSafeBox.DoUpgradeToProtocol2: Boolean;
var
    block_number: Cardinal;
    aux: TRawBytes;
begin
    // Upgrade process to protocol 2
    Result := false;
    If Not CanUpgradeToProtocol2 then
        exit;
    // Recalc all BlockAccounts block_hash value
    aux := CalcSafeBoxHash;
    TLog.NewLog(ltInfo, Classname, 'Start Upgrade to protocol 2 - Old Safeboxhash:' + TCrypto.ToHexaString(FSafeBoxHash) + ' calculated: ' +
      TCrypto.ToHexaString(aux) + ' Blocks: ' + inttostr(blocksCount));
    FBufferBlocksHash := '';
    for block_number := 0 to blocksCount - 1 do
    begin
{$IFDEF uselowmem}
        TBaseType.To32Bytes(CalcBlockHash(block(block_number), true), PBlockAccount(FBlockAccountsList.Items[block_number])^.block_hash);
        FBufferBlocksHash := FBufferBlocksHash + TBaseType.ToRawBytes(PBlockAccount(FBlockAccountsList.Items[block_number])^.block_hash);
{$ELSE}
        PBlockAccount(FBlockAccountsList.Items[block_number])^.block_hash := CalcBlockHash(block(block_number), true);
        FBufferBlocksHash := FBufferBlocksHash + PBlockAccount(FBlockAccountsList.Items[block_number])^.block_hash;
{$ENDIF}
    end;
    FSafeBoxHash := CalcSafeBoxHash;
    FCurrentProtocol := CT_PROTOCOL_2;
    Result := true;
    TLog.NewLog(ltInfo, Classname, 'End Upgraded to protocol 2 - New safeboxhash:' + TCrypto.ToHexaString(FSafeBoxHash));
end;

procedure TPCSafeBox.EndThreadSave;
begin
    FLock.Release;
end;

function TPCSafeBox.LoadSafeBoxFromStream(stream: TStream; checkAll: Boolean; var LastReadBlock: TBlockAccount; var errors: AnsiString): Boolean;
Var
    iblock, iacc: Cardinal;
    s: AnsiString;
    block: TBlockAccount;
    P: PBlockAccount;
    i, j: Integer;
    savedSBH: TRawBytes;
    nPos, posOffsetZone: Int64;
    offsets: Array of Cardinal;
    sbHeader: TPCSafeBoxHeader;
begin
    StartThreadSafe;
    try
        Clear;
        Result := false;
        Try
            If not LoadSafeBoxStreamHeader(stream, sbHeader) then
            begin
                errors := 'Invalid stream. Invalid header/version';
                exit;
            end;
            errors := 'Invalid version or corrupted stream';
            case sbHeader.protocol of
                CT_PROTOCOL_1:
                    FCurrentProtocol := 1;
                CT_PROTOCOL_2:
                    FCurrentProtocol := 2;
            else
                exit;
            end;
            if (sbHeader.blocksCount = 0) Or (sbHeader.startBlock <> 0) Or (sbHeader.endBlock <> (sbHeader.blocksCount - 1)) then
            begin
                errors := Format('Safebox Stream contains blocks from %d to %d (of %d blocks). Not valid',
                  [sbHeader.startBlock, sbHeader.endBlock, sbHeader.blocksCount]);
                exit;
            end;
            // Offset zone
            posOffsetZone := stream.Position;
            If checkAll then
            begin
                SetLength(offsets, sbHeader.blocksCount + 1); // Last offset = End of blocks
                stream.Read(offsets[0], 4 * (sbHeader.blocksCount + 1));
            end
            else
            begin
                nPos := stream.Position + ((sbHeader.blocksCount + 1) * 4);
                if stream.Size < nPos then
                    exit;
                stream.Position := nPos;
            end;
            // Build 1.3.0 to increase reading speed:
            FBlockAccountsList.Capacity := sbHeader.blocksCount;
            SetLength(FBufferBlocksHash, sbHeader.blocksCount * 32); // Initialize for high speed reading
            errors := 'Corrupted stream';
            for iblock := 0 to sbHeader.blocksCount - 1 do
            begin
                errors := 'Corrupted stream reading block blockchain ' + inttostr(iblock + 1) + '/' + inttostr(sbHeader.blocksCount);
                if (checkAll) then
                begin
                    If (offsets[iblock] <> stream.Position - posOffsetZone) then
                    begin
                        errors := errors + Format(' - offset[%d]:%d <> %d Position:%d offset:%d', [iblock, offsets[iblock], stream.Position - posOffsetZone,
                          stream.Position, posOffsetZone]);
                        exit;
                    end;
                end;

                block := CT_BlockAccount_NUL;
                If Not TAccountComp.LoadTOperationBlockFromStream(stream, block.blockchainInfo) then
                    exit;
                if block.blockchainInfo.block <> iblock then
                    exit;
                for iacc := Low(block.accounts) to High(block.accounts) do
                begin
                    errors := 'Corrupted stream reading account ' + inttostr(iacc + 1) + '/' + inttostr(length(block.accounts)) + ' of block ' +
                      inttostr(iblock + 1) + '/' + inttostr(sbHeader.blocksCount);
                    if stream.Read(block.accounts[iacc].account, 4) < 4 then
                        exit;
                    if TStreamOp.ReadAnsiString(stream, s) < 0 then
                        exit;
                    block.accounts[iacc].accountInfo := TAccountComp.RawString2AccountInfo(s);
                    if stream.Read(block.accounts[iacc].balance, Sizeof(UInt64)) < Sizeof(UInt64) then
                        exit;
                    if stream.Read(block.accounts[iacc].updated_block, 4) < 4 then
                        exit;
                    if stream.Read(block.accounts[iacc].n_operation, 4) < 4 then
                        exit;
                    If FCurrentProtocol >= CT_PROTOCOL_2 then
                    begin
                        if TStreamOp.ReadAnsiString(stream, block.accounts[iacc].name) < 0 then
                            exit;
                        if stream.Read(block.accounts[iacc].account_type, 2) < 2 then
                            exit;
                    end;
                    //
                    if stream.Read(block.accounts[iacc].previous_updated_block, 4) < 4 then
                        exit;
                    // check valid
                    If (block.accounts[iacc].name <> '') then
                    begin
                        if FOrderedByName.IndexOf(block.accounts[iacc].name) >= 0 then
                        begin
                            errors := errors + ' Duplicate name "' + block.accounts[iacc].name + '"';
                            exit;
                        end;
                        if Not TPCSafeBox.ValidAccountName(block.accounts[iacc].name, s) then
                        begin
                            errors := errors + ' > Invalid name "' + block.accounts[iacc].name + '": ' + s;
                            exit;
                        end;
                        FOrderedByName.Add(block.accounts[iacc].name, block.accounts[iacc].account);
                    end;
                    If checkAll then
                    begin
                        if not TAccountComp.IsValidAccountInfo(block.accounts[iacc].accountInfo, s) then
                        begin
                            errors := errors + ' > ' + s;
                            exit;
                        end;
                    end;
                    inc(FTotalBalance, block.accounts[iacc].balance);
                end;
                errors := 'Corrupted stream reading block ' + inttostr(iblock + 1) + '/' + inttostr(sbHeader.blocksCount);
                If TStreamOp.ReadAnsiString(stream, block.block_hash) < 0 then
                    exit;
                If stream.Read(block.accumulatedWork, Sizeof(block.accumulatedWork)) < Sizeof(block.accumulatedWork) then
                    exit;
                if checkAll then
                begin
                    // Check is valid:
                    // STEP 1: Validate the block
                    If not IsValidNewOperationsBlock(block.blockchainInfo, false, s) then
                    begin
                        errors := errors + ' > ' + s;
                        exit;
                    end;
                    // STEP 2: Check if valid block hash
                    if CalcBlockHash(block, FCurrentProtocol >= CT_PROTOCOL_2) <> block.block_hash then
                    begin
                        errors := errors + ' > Invalid block hash ' + inttostr(iblock + 1) + '/' + inttostr(sbHeader.blocksCount);
                        exit;
                    end;
                    // STEP 3: Check accumulatedWork
                    if (iblock > 0) then
                    begin
                        If (Self.block(iblock - 1).accumulatedWork) + block.blockchainInfo.compact_target <> block.accumulatedWork then
                        begin
                            errors := errors + ' > Invalid accumulatedWork';
                            exit;
                        end;
                    end;
                end;
                // Add
                New(P);
                ToTMemBlockAccount(block, P^);
                FBlockAccountsList.Add(P);
                for j := low(block.accounts) to High(block.accounts) do
                begin
                    AccountKeyListAddAccounts(block.accounts[j].accountInfo.accountKey, [block.accounts[j].account]);
                end;
                // BufferBlocksHash fill with data
                j := (length(P^.block_hash) * (iblock));
                for i := 1 to length(P^.block_hash) do
                begin
{$IFDEF FPC}
                    FBufferBlocksHash[i + j] := AnsiChar(P^.block_hash[i - (low(FBufferBlocksHash) - low(P^.block_hash))]);
{$ELSE}
                    FBufferBlocksHash[i + j] := AnsiChar(P^.block_hash[i - {$IFDEF uselowmem}1{$ELSE}0{$ENDIF}]);
{$ENDIF}
                end;
                LastReadBlock := block;
                inc(FWorkSum, block.blockchainInfo.compact_target);
            end;
            If checkAll then
            begin
                If (offsets[sbHeader.blocksCount] <> 0) And (offsets[sbHeader.blocksCount] <> stream.Position - posOffsetZone) then
                begin
                    errors := errors + Format(' - Final offset[%d]=%d <> Eof Position:%d offset:%d', [sbHeader.blocksCount, offsets[sbHeader.blocksCount],
                      stream.Position - posOffsetZone, posOffsetZone]);
                    exit;
                end;
            end;
            // Finally load SafeBoxHash
            If TStreamOp.ReadAnsiString(stream, savedSBH) < 0 then
            begin
                errors := 'No SafeBoxHash value';
                exit;
            end;
            // Check worksum value
            If sbHeader.blocksCount > 0 then
            begin
                If (FWorkSum <> Self.block(sbHeader.blocksCount - 1).accumulatedWork) then
                begin
                    errors := 'Invalid WorkSum value';
                    exit;
                end;
            end;
            // Calculating safe box hash
            FSafeBoxHash := CalcSafeBoxHash;
            // Checking saved SafeBoxHash
            If FSafeBoxHash <> savedSBH then
            begin
                errors := 'Invalid SafeBoxHash value in stream ' + TCrypto.ToHexaString(FSafeBoxHash) + '<>' + TCrypto.ToHexaString(savedSBH) + ' Last block:' +
                  inttostr(LastReadBlock.blockchainInfo.block);
                exit;
            end;
            Result := true;
        Finally
            if Not Result then
                Clear
            else
                errors := '';
        End;
    Finally
        EndThreadSave;
    end;
end;

class function TPCSafeBox.LoadSafeBoxStreamHeader(stream: TStream; var sbHeader: TPCSafeBoxHeader): Boolean;
// This function reads SafeBox stream info and sets position at offset start zone if valid, otherwise sets position to actual position
Var
    w: Word;
    s: AnsiString;
    safeBoxBankVersion: Word;
    offsetPos, initialPos: Int64;
    endBlocks: Cardinal;
begin
    Result := false;
    sbHeader := CT_PCSafeBoxHeader_NUL;
    initialPos := stream.Position;
    try
        TStreamOp.ReadAnsiString(stream, s);
        if (s <> CT_MagicIdentificator) then
            exit;
        if stream.Size < 8 then
            exit;
        stream.Read(w, Sizeof(w));
        if not(w in [1, 2]) then
            exit;
        sbHeader.protocol := w;
        stream.Read(safeBoxBankVersion, 2);
        if safeBoxBankVersion <> CT_SafeBoxBankVersion then
            exit;
        stream.Read(sbHeader.blocksCount, 4);
        stream.Read(sbHeader.startBlock, 4);
        stream.Read(sbHeader.endBlock, 4);
        if (sbHeader.blocksCount <= 0) Or (sbHeader.blocksCount > (CT_NewLineSecondsAvg * 2000000)) then
            exit; // Protection for corrupted data...
        offsetPos := stream.Position;
        // Go to read SafeBoxHash
        If (stream.Size < offsetPos + (((sbHeader.endBlock - sbHeader.startBlock) + 2) * 4)) then
            exit;
        stream.Position := offsetPos + (((sbHeader.endBlock - sbHeader.startBlock) + 1) * 4);
        stream.Read(endBlocks, 4);
        // Go to end
        If (stream.Size < offsetPos + (endBlocks)) then
            exit;
        stream.Position := offsetPos + endBlocks;
        If TStreamOp.ReadAnsiString(stream, sbHeader.safeBoxHash) < 0 then
            exit;
        // Back
        stream.Position := offsetPos;
        Result := true;
    finally
        If not Result then
            stream.Position := initialPos;
    end;
end;

class function TPCSafeBox.SaveSafeBoxStreamHeader(stream: TStream; protocol: Word;
  OffsetStartBlock, OffsetEndBlock, CurrentSafeBoxBlocksCount: Cardinal): Boolean;
var
    c: Cardinal;
begin
    Result := false;
    // Header zone
    TStreamOp.WriteAnsiString(stream, CT_MagicIdentificator);
    stream.Write(protocol, Sizeof(protocol));
    stream.Write(CT_SafeBoxBankVersion, Sizeof(CT_SafeBoxBankVersion));
    c := CurrentSafeBoxBlocksCount;
    stream.Write(c, Sizeof(c)); // Save Total blocks of the safebox
    c := OffsetStartBlock;
    stream.Write(c, Sizeof(c)); // Save first block saved
    c := OffsetEndBlock;
    stream.Write(c, Sizeof(c)); // Save last block saved
    Result := true;
end;

class function TPCSafeBox.MustSafeBoxBeSaved(blocksCount: Cardinal): Boolean;
begin
    Result := (blocksCount MOD CT_BankToDiskEveryNBlocks) = 0;
end;

procedure TPCSafeBox.SaveSafeBoxBlockToAStream(stream: TStream; nBlock: Cardinal);
var
    b: TBlockAccount;
    iacc: Integer;
begin
    b := block(nBlock);
    TAccountComp.SaveTOperationBlockToStream(stream, b.blockchainInfo);
    for iacc := Low(b.accounts) to High(b.accounts) do
    begin
        stream.Write(b.accounts[iacc].account, Sizeof(b.accounts[iacc].account));
        TStreamOp.WriteAnsiString(stream, TAccountComp.AccountInfo2RawString(b.accounts[iacc].accountInfo));
        stream.Write(b.accounts[iacc].balance, Sizeof(b.accounts[iacc].balance));
        stream.Write(b.accounts[iacc].updated_block, Sizeof(b.accounts[iacc].updated_block));
        stream.Write(b.accounts[iacc].n_operation, Sizeof(b.accounts[iacc].n_operation));
        If FCurrentProtocol >= CT_PROTOCOL_2 then
        begin
            TStreamOp.WriteAnsiString(stream, b.accounts[iacc].name);
            stream.Write(b.accounts[iacc].account_type, Sizeof(b.accounts[iacc].account_type));
        end;
        stream.Write(b.accounts[iacc].previous_updated_block, Sizeof(b.accounts[iacc].previous_updated_block));
    end;
    TStreamOp.WriteAnsiString(stream, b.block_hash);
    stream.Write(b.accumulatedWork, Sizeof(b.accumulatedWork));
end;

procedure TPCSafeBox.SaveSafeBoxToAStream(stream: TStream; FromBlock, ToBlock: Cardinal);
Var
    totalBlocks, iblock: Cardinal;
    b: TBlockAccount;
    posOffsetZone, posFinal: Int64;
    offsets: TCardinalsArray;
    raw: TRawBytes;
begin
    If (FromBlock > ToBlock) Or (ToBlock >= blocksCount) then
        Raise Exception.Create(Format('Cannot save SafeBox from %d to %d (currently %d blocks)', [FromBlock, ToBlock, blocksCount]));
    StartThreadSafe;
    Try
        // Header zone
        SaveSafeBoxStreamHeader(stream, FCurrentProtocol, FromBlock, ToBlock, blocksCount);
        totalBlocks := ToBlock - FromBlock + 1;
        // Offsets zone
        posOffsetZone := stream.Position;
        SetLength(raw, (totalBlocks + 1) * 4); // Last position = end
        FillChar(raw[1], length(raw), 0);
        stream.WriteBuffer(raw[1], length(raw));
        SetLength(offsets, totalBlocks + 1); // c = total blocks  - Last position = offset to end
        // Blocks zone
        for iblock := FromBlock to ToBlock do
        begin
            offsets[iblock] := stream.Position - posOffsetZone;
            SaveSafeBoxBlockToAStream(stream, iblock);
        end;
        offsets[High(offsets)] := stream.Position - posOffsetZone;
        // Save offsets zone with valid values
        posFinal := stream.Position;
        stream.Position := posOffsetZone;
        for iblock := FromBlock to ToBlock + 1 do
        begin
            stream.Write(offsets[iblock], Sizeof(offsets[iblock]));
        end;
        stream.Position := posFinal;
        // Final zone: Save safeboxhash for next block
        If (ToBlock + 1 < blocksCount) then
        begin
            b := block(ToBlock);
            TStreamOp.WriteAnsiString(stream, b.blockchainInfo.initial_safe_box_hash);
        end
        else
        begin
            TStreamOp.WriteAnsiString(stream, FSafeBoxHash);
        end;
    Finally
        EndThreadSave;
    end;
end;

class function TPCSafeBox.CopySafeBoxStream(Source, dest: TStream; FromBlock, ToBlock: Cardinal; var errors: AnsiString): Boolean;
Var
    iblock: Cardinal;
    raw: TRawBytes;
    posOffsetZoneSource, posOffsetZoneDest, posFinal, posBlocksZoneDest, posInitial: Int64;
    offsetsSource, offsetsDest: TCardinalsArray;
    destTotalBlocks: Cardinal;
    sbHeader: TPCSafeBoxHeader;
begin
    Result := false;
    errors := '';
    posInitial := Source.Position;
    try
        If (FromBlock > ToBlock) then
        begin
            errors := Format('Invalid CopySafeBoxStream(from %d, to %d)', [FromBlock, ToBlock]);
            exit;
        end;
        If not LoadSafeBoxStreamHeader(Source, sbHeader) then
        begin
            errors := 'Invalid stream. Invalid header/version';
            exit;
        end;
        if (sbHeader.startBlock > FromBlock) Or (sbHeader.endBlock < ToBlock) Or ((sbHeader.startBlock + sbHeader.blocksCount) < ToBlock) then
        begin
            errors := Format('Stream contain blocks from %d to %d (of %d). Need between %d and %d !',
              [sbHeader.startBlock, sbHeader.endBlock, sbHeader.blocksCount, FromBlock, ToBlock]);
            exit;
        end;
        destTotalBlocks := ToBlock - FromBlock + 1;
        TLog.NewLog(ltInfo, Classname, Format('CopySafeBoxStream from safebox with %d to %d (of %d sbh:%s) to safebox with %d and %d',
          [sbHeader.startBlock, sbHeader.endBlock, sbHeader.blocksCount, TCrypto.ToHexaString(sbHeader.safeBoxHash), FromBlock, ToBlock]));
        // Read Source Offset zone
        posOffsetZoneSource := Source.Position;
        SetLength(offsetsSource, (sbHeader.endBlock - sbHeader.startBlock) + 2);
        Source.Read(offsetsSource[0], 4 * length(offsetsSource));
        // DEST STREAM:
        // Init dest stream
        // Header zone
        SaveSafeBoxStreamHeader(dest, sbHeader.protocol, FromBlock, ToBlock, sbHeader.blocksCount);
        // Offsets zone
        posOffsetZoneDest := dest.Position;
        SetLength(raw, (destTotalBlocks + 1) * 4); // Cardinal = 4 bytes for each block + End position
        FillChar(raw[1], length(raw), 0);
        dest.WriteBuffer(raw[1], length(raw));
        SetLength(offsetsDest, destTotalBlocks + 1);
        // Blocks zone
        posBlocksZoneDest := dest.Position;
        TLog.NewLog(ltInfo, Classname, Format('Copying Safebox Stream from source Position %d (size:%d) to dest %d bytes - OffsetSource[%d] - OffsetSource[%d]',
          [posOffsetZoneSource + offsetsSource[FromBlock - sbHeader.startBlock], Source.Size, offsetsSource[ToBlock - sbHeader.startBlock + 1] -
          offsetsSource[FromBlock - sbHeader.startBlock], ToBlock - sbHeader.startBlock + 1, FromBlock - sbHeader.startBlock]));

        Source.Position := posOffsetZoneSource + offsetsSource[FromBlock - sbHeader.startBlock];
        dest.CopyFrom(Source, offsetsSource[ToBlock - sbHeader.startBlock + 1] - offsetsSource[FromBlock - sbHeader.startBlock]);
        // Save offsets zone with valid values
        posFinal := dest.Position;
        dest.Position := posOffsetZoneDest;
        for iblock := FromBlock to ToBlock do
        begin
            offsetsDest[iblock - FromBlock] := offsetsSource[iblock - (sbHeader.startBlock)] - offsetsSource[FromBlock - sbHeader.startBlock] +
              (posBlocksZoneDest - posOffsetZoneDest);
        end;
        offsetsDest[high(offsetsDest)] := posFinal - posOffsetZoneDest;

        dest.WriteBuffer(offsetsDest[0], length(offsetsDest) * 4);
        dest.Position := posFinal;
        Source.Position := offsetsSource[High(offsetsSource)] + posOffsetZoneSource;
        TStreamOp.ReadAnsiString(Source, raw);
        TStreamOp.WriteAnsiString(dest, raw);
        Result := true;
    finally
        Source.Position := posInitial;
    end;
end;

class function TPCSafeBox.ConcatSafeBoxStream(Source1, Source2, dest: TStream; var errors: AnsiString): Boolean;
    function MinCardinal(v1, v2: Cardinal): Cardinal;
    begin
        if v1 < v2 then
            Result := v1
        else
            Result := v2;
    end;
    function MaxCardinal(v1, v2: Cardinal): Cardinal;
    begin
        if v1 > v2 then
            Result := v1
        else
            Result := v2;
    end;
    function ReadSafeBoxBlockFromStream(safeBoxStream: TStream; offsetIndex: Cardinal; destStream: TStream): Cardinal;
    // PRE: safeBoxStream is a valid SafeBox Stream (with enough size) located at Offsets zone, and offsetIndex is >=0 and <= end block
    // Returns the size of the saved block at destStream
    var
        offsetPos, auxPos: Int64;
        c, cNext: Cardinal;
    begin
        Result := 0;
        offsetPos := safeBoxStream.Position;
        try
            safeBoxStream.Seek(4 * offsetIndex, soFromCurrent);
            safeBoxStream.Read(c, 4);
            safeBoxStream.Read(cNext, 4);
            if cNext < c then
                exit;
            Result := cNext - c; // Result is the offset difference between blocks
            if Result <= 0 then
                exit;
            auxPos := offsetPos + c;
            if safeBoxStream.Size < auxPos + Result then
                exit; // Invalid
            safeBoxStream.Position := auxPos;
            destStream.CopyFrom(safeBoxStream, Result);
        finally
            safeBoxStream.Position := offsetPos;
        end;
    end;

    procedure WriteSafeBoxBlockToStream(stream, safeBoxStream: TStream; nBytes: Integer; offsetIndex, totalOffsets: Cardinal);
    // PRE: safeBoxStream is a valid SafeBox Stream located at Offsets zone, and offsetIndex=0 or offsetIndex-1 has a valid value
    var
        offsetPos: Int64;
        c, cLength: Cardinal;
    begin
        offsetPos := safeBoxStream.Position;
        try
            if offsetIndex = 0 then
            begin
                // First
                c := ((totalOffsets + 1) * 4);
                safeBoxStream.Write(c, 4);
            end
            else
            begin
                safeBoxStream.Seek(4 * (offsetIndex), soFromCurrent);
                safeBoxStream.Read(c, 4); // c is position
            end;
            cLength := c + nBytes;
            safeBoxStream.Write(cLength, 4);
            safeBoxStream.Position := offsetPos + c;
            safeBoxStream.CopyFrom(stream, nBytes);
        finally
            safeBoxStream.Position := offsetPos;
        end;
    end;

Var
    destStartBlock, destEndBlock, nBlock: Cardinal;
    source1InitialPos, source2InitialPos, destOffsetPos: Int64;
    ms: TMemoryStream;
    c: Cardinal;
    destOffsets: TCardinalsArray;
    i: Integer;
    s1Header, s2Header: TPCSafeBoxHeader;
begin
    Result := false;
    errors := '';
    source1InitialPos := Source1.Position;
    source2InitialPos := Source2.Position;
    Try
        If not LoadSafeBoxStreamHeader(Source1, s1Header) then
        begin
            errors := 'Invalid source 1 stream. Invalid header/version';
            exit;
        end;
        If not LoadSafeBoxStreamHeader(Source2, s2Header) then
        begin
            errors := 'Invalid source 2 stream. Invalid header/version';
            exit;
        end;
        // Check SBH and blockcount
        if (s1Header.safeBoxHash <> s2Header.safeBoxHash) or (s1Header.blocksCount <> s2Header.blocksCount) Or (s1Header.protocol <> s2Header.protocol) then
        begin
            errors := Format('Source1 and Source2 have diff safebox. Source 1 %d %s (protocol %d) Source 2 %d %s (protocol %d)',
              [s1Header.blocksCount, TCrypto.ToHexaString(s1Header.safeBoxHash), s1Header.protocol, s2Header.blocksCount,
              TCrypto.ToHexaString(s2Header.safeBoxHash), s2Header.protocol]);
            exit;
        end;
        // Save dest heaer
        destStartBlock := MinCardinal(s1Header.startBlock, s2Header.startBlock);
        destEndBlock := MaxCardinal(s1Header.endBlock, s2Header.endBlock);
        SaveSafeBoxStreamHeader(dest, s1Header.protocol, destStartBlock, destEndBlock, s1Header.blocksCount);
        // Save offsets
        destOffsetPos := dest.Position;
        SetLength(destOffsets, ((destEndBlock - destStartBlock) + 2));
        for i := low(destOffsets) to high(destOffsets) do
            destOffsets[i] := 0;
        dest.Write(destOffsets[0], ((destEndBlock - destStartBlock) + 2) * 4);
        dest.Position := destOffsetPos;
        //
        nBlock := destStartBlock;
        ms := TMemoryStream.Create;
        try
            for nBlock := destStartBlock to destEndBlock do
            begin
                ms.Clear;
                if (nBlock >= s1Header.startBlock) And (nBlock <= s1Header.endBlock) then
                begin
                    c := ReadSafeBoxBlockFromStream(Source1, nBlock - s1Header.startBlock, ms);
                    ms.Position := 0;
                    WriteSafeBoxBlockToStream(ms, dest, c, nBlock - destStartBlock, destEndBlock - destStartBlock + 1);
                end
                else if (nBlock >= s2Header.startBlock) and (nBlock <= s2Header.endBlock) then
                begin
                    c := ReadSafeBoxBlockFromStream(Source2, nBlock - s2Header.startBlock, ms);
                    ms.Position := 0;
                    WriteSafeBoxBlockToStream(ms, dest, c, nBlock - destStartBlock, destEndBlock - destStartBlock + 1);
                end
                else
                    Raise Exception.Create('ERROR DEV 20170518-1');
            end;
        Finally
            ms.Free;
        end;
        // Save SafeBoxHash at the end
        dest.Seek(0, soFromEnd);
        TStreamOp.WriteAnsiString(dest, s1Header.safeBoxHash);
        Result := true;
    Finally
        Source1.Position := source1InitialPos;
        Source2.Position := source2InitialPos;
    end;
end;

class function TPCSafeBox.ValidAccountName(const new_name: TRawBytes; var errors: AnsiString): Boolean;
{ Note:
  This function is case senstive, and only lower case chars are valid.
  Execute a LowerCase() prior to call this function!
}
Const
    CT_PascalCoin_Base64_Charset: ShortString = 'abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-+{}[]\_:"|<>,.?/~';
    // First char can't start with a number
    CT_PascalCoin_FirstChar_Charset: ShortString = 'abcdefghijklmnopqrstuvwxyz!@#$%^&*()-+{}[]\_:"|<>,.?/~';
    CT_PascalCoin_name_min_length = 3;
    CT_PascalCoin_name_max_length = 64;
var
    i, j: Integer;
begin
    Result := false;
    errors := '';
    if (length(new_name) < CT_PascalCoin_name_min_length) Or (length(new_name) > CT_PascalCoin_name_max_length) then
    begin
        errors := 'Invalid length:' + inttostr(length(new_name)) + ' (valid from ' + inttostr(CT_PascalCoin_name_max_length) + ' to ' +
          inttostr(CT_PascalCoin_name_max_length) + ')';
        exit;
    end;
    for i := 1 to length(new_name) do
    begin
        j := 1;
        if (i = 1) then
        begin
            // First char can't start with a number
            While (j <= length(CT_PascalCoin_FirstChar_Charset)) and (new_name[i] <> CT_PascalCoin_FirstChar_Charset[j]) do
                inc(j);
            if j > length(CT_PascalCoin_FirstChar_Charset) then
            begin
                errors := 'Invalid char ' + new_name[i] + ' at first pos';
                exit; // Not found
            end;
        end
        else
        begin
            While (j <= length(CT_PascalCoin_Base64_Charset)) and (new_name[i] <> CT_PascalCoin_Base64_Charset[j]) do
                inc(j);
            if j > length(CT_PascalCoin_Base64_Charset) then
            begin
                errors := 'Invalid char ' + new_name[i] + ' at pos ' + inttostr(i);
                exit; // Not found
            end;
        end;
    end;
    Result := true;
end;

function TPCSafeBox.IsValidNewOperationsBlock(const newOperationBlock: TOperationBlock; checkSafeBoxHash: Boolean; var errors: AnsiString): Boolean;
{ This function will check a OperationBlock info as a valid candidate to be included in the safebox

  TOperationBlock contains the info of the new block EXCEPT the operations, including only operations_hash value (SHA256 of the Operations)
  So, cannot check operations and fee values
}
var
    target_hash, PoW: TRawBytes;
    i: Integer;
    lastBlock: TOperationBlock;
begin
    Result := false;
    errors := '';
    If blocksCount > 0 then
        lastBlock := block(blocksCount - 1).blockchainInfo
    else
        lastBlock := CT_OperationBlock_NUL;
    // Check block
    if (blocksCount <> newOperationBlock.block) then
    begin
        errors := 'block (' + inttostr(newOperationBlock.block) + ') is not new position (' + inttostr(blocksCount) + ')';
        exit;
    end;
    // Check Account key
    if Not TAccountComp.IsValidAccountKey(newOperationBlock.account_key, errors) then
    begin
        exit;
    end;
    // reward
    if (newOperationBlock.reward <> TPascalCoinProtocol.GetRewardForNewLine(newOperationBlock.block)) then
    begin
        errors := 'Invalid reward';
        exit;
    end;
    // fee: Cannot be checked only with the safebox
    // protocol available is not checked
    if (newOperationBlock.block > 0) then
    begin
        // protocol
        if (newOperationBlock.protocol_version <> CurrentProtocol) then
        begin
            // Protocol must be 1 or 2. If 1 then all prior blocksmust be 1 and never 2 (invalide blockchain version scenario v1...v2...v1)
            If (lastBlock.protocol_version > newOperationBlock.protocol_version) then
            begin
                errors := 'Invalid PascalCoin protocol version: ' + inttostr(newOperationBlock.protocol_version) + ' Current: ' + inttostr(CurrentProtocol) +
                  ' Previous:' + inttostr(lastBlock.protocol_version);
                exit;
            end;
            If (newOperationBlock.protocol_version = CT_PROTOCOL_2) then
            begin
                If (newOperationBlock.block < CT_Protocol_Upgrade_v2_MinBlock) then
                begin
                    errors := 'Upgrade to protocol version 2 available at block: ' + inttostr(CT_Protocol_Upgrade_v2_MinBlock);
                    exit;
                end;
            end
            else if (newOperationBlock.protocol_version <> CT_PROTOCOL_1) then
            begin
                errors := 'Invalid protocol version change to ' + inttostr(newOperationBlock.protocol_version);
                exit;
            end;
        end
        else if (Not(newOperationBlock.protocol_version in [CT_PROTOCOL_1, CT_PROTOCOL_2])) then
        begin
            errors := 'Invalid protocol version ' + inttostr(newOperationBlock.protocol_version);
            exit;
        end;
        // timestamp
        if ((newOperationBlock.timestamp) < (lastBlock.timestamp)) then
        begin
            errors := 'Invalid timestamp (Back timestamp: New timestamp:' + inttostr(newOperationBlock.timestamp) + ' < last timestamp (' +
              inttostr(blocksCount - 1) + '):' + inttostr(lastBlock.timestamp) + ')';
            exit;
        end;
    end
    else
    begin
        if (CT_Zero_Block_Proof_of_work_in_Hexa <> '') then
        begin
            // Check if valid Zero block
            if Not(AnsiSameText(TCrypto.ToHexaString(newOperationBlock.proof_of_work), CT_Zero_Block_Proof_of_work_in_Hexa)) then
            begin
                errors := 'Zero block not valid, Proof of Work invalid: ' + TCrypto.ToHexaString(newOperationBlock.proof_of_work) + '<>' +
                  CT_Zero_Block_Proof_of_work_in_Hexa;
                exit;
            end;
        end;
    end;
    // compact_target
    target_hash := GetActualTargetHash(newOperationBlock.protocol_version = CT_PROTOCOL_2);
    if (newOperationBlock.compact_target <> TPascalCoinProtocol.TargetToCompact(target_hash)) then
    begin
        errors := 'Invalid target found:' + IntToHex(newOperationBlock.compact_target, 8) + ' actual:' +
          IntToHex(TPascalCoinProtocol.TargetToCompact(target_hash), 8);
        exit;
    end;
    // nonce: Not checked
    // block_payload: Checking Miner payload size
    if length(newOperationBlock.block_payload) > CT_MaxPayloadSize then
    begin
        errors := 'Invalid Miner Payload length: ' + inttostr(length(newOperationBlock.block_payload));
        exit;
    end;
    // Checking Miner Payload valid chars
    for i := 1 to length(newOperationBlock.block_payload) do
    begin
        if Not(newOperationBlock.block_payload[i] in [#32 .. #254]) then
        begin
            errors := 'Invalid Miner Payload character at pos ' + inttostr(i) + ' value:' + inttostr(ord(newOperationBlock.block_payload[i]));
            exit;
        end;
    end;
    // initial_safe_box_hash: Only can be checked when adding new blocks, not when restoring a safebox
    If checkSafeBoxHash then
    begin
        // TODO: Can use FSafeBoxHash instead of CalcSafeBoxHash ???? Quick speed if possible
        if (newOperationBlock.initial_safe_box_hash <> CalcSafeBoxHash) then
        begin
            errors := 'BlockChain Safe box hash invalid: ' + TCrypto.ToHexaString(newOperationBlock.initial_safe_box_hash) + ' var: ' +
              TCrypto.ToHexaString(FSafeBoxHash) + ' Calculated:' + TCrypto.ToHexaString(CalcSafeBoxHash);
            exit;
        end;
    end;
    // operations_hash: NOT CHECKED WITH OPERATIONS!
    If (length(newOperationBlock.operations_hash) <> 32) then
    begin
        errors := 'Invalid Operations hash value: ' + TCrypto.ToHexaString(newOperationBlock.operations_hash) + ' length=' +
          inttostr(length(newOperationBlock.operations_hash));
        exit;
    end;
    // proof_of_work:
    TPascalCoinProtocol.CalcProofOfWork(newOperationBlock, PoW);
    if (PoW <> newOperationBlock.proof_of_work) then
    begin
        errors := 'Proof of work is bad calculated ' + TCrypto.ToHexaString(newOperationBlock.proof_of_work) + ' <> Good: ' + TCrypto.ToHexaString(PoW);
        exit;
    end;
    if (newOperationBlock.proof_of_work > target_hash) then
    begin
        errors := 'Proof of work is higher than target ' + TCrypto.ToHexaString(newOperationBlock.proof_of_work) + ' > ' + TCrypto.ToHexaString(target_hash);
        exit;
    end;
    Result := true;
end;

function TPCSafeBox.GetActualTargetHash(UseProtocolV2: Boolean): TRawBytes;
{ Target is calculated in each block with avg obtained in previous
  CT_CalcNewDifficulty blocks.
  If Block is lower than CT_CalcNewDifficulty then is calculated
  with all previous blocks.
}
Var
    ts1, ts2, tsTeorical, tsReal, tsTeoricalStop, tsRealStop: Int64;
    CalcBack: Integer;
    lastBlock: TOperationBlock;
begin
    if (blocksCount <= 1) then
    begin
        // Important: CT_MinCompactTarget is applied for blocks 0 until ((CT_CalcNewDifficulty*2)-1)
        Result := TPascalCoinProtocol.TargetFromCompact(CT_MinCompactTarget);
    end
    else
    begin
        if blocksCount > CT_CalcNewTargetBlocksAverage then
            CalcBack := CT_CalcNewTargetBlocksAverage
        else
            CalcBack := blocksCount - 1;
        lastBlock := block(blocksCount - 1).blockchainInfo;
        // Calc new target!
        ts1 := lastBlock.timestamp;
        ts2 := block(blocksCount - CalcBack - 1).blockchainInfo.timestamp;
        tsTeorical := (CalcBack * CT_NewLineSecondsAvg);
        tsReal := (ts1 - ts2);
        If (Not UseProtocolV2) then
        begin
            Result := TPascalCoinProtocol.GetNewTarget(tsTeorical, tsReal, TPascalCoinProtocol.TargetFromCompact(lastBlock.compact_target));
        end
        else
        begin
            CalcBack := CalcBack DIV CT_CalcNewTargetLimitChange_SPLIT;
            If CalcBack = 0 then
                CalcBack := 1;
            ts2 := block(blocksCount - CalcBack - 1).blockchainInfo.timestamp;
            tsTeoricalStop := (CalcBack * CT_NewLineSecondsAvg);
            tsRealStop := (ts1 - ts2);
            { Protocol 2 change:
              Only will increase/decrease Target if (CT_CalcNewTargetBlocksAverage DIV 10) needs to increase/decrease too, othewise use
              current Target.
              This will prevent sinusoidal movement and provide more stable hashrate, computing always time from CT_CalcNewTargetBlocksAverage }
            If ((tsTeorical > tsReal) and (tsTeoricalStop > tsRealStop)) Or ((tsTeorical < tsReal) and (tsTeoricalStop < tsRealStop)) then
            begin
                Result := TPascalCoinProtocol.GetNewTarget(tsTeorical, tsReal, TPascalCoinProtocol.TargetFromCompact(lastBlock.compact_target));
            end
            else
            begin
                // Nothing to do!
                Result := TPascalCoinProtocol.TargetFromCompact(lastBlock.compact_target);
            end;
        end;
    end;
end;

function TPCSafeBox.GetActualCompactTargetHash(UseProtocolV2: Boolean): Cardinal;
begin
    Result := TPascalCoinProtocol.TargetToCompact(GetActualTargetHash(UseProtocolV2));
end;

function TPCSafeBox.FindAccountByName(aName: AnsiString): Integer;
Var
    nameLower: AnsiString;
    i: Integer;
begin
    nameLower := LowerCase(aName);
    i := FOrderedByName.IndexOf(aName);
    if i >= 0 then
        Result := FOrderedByName.GetTag(i)
    else
        Result := -1;
end;

procedure TPCSafeBox.SetAccount(account_number: Cardinal; const newAccountInfo: TAccountInfo; const newName: TRawBytes; newType: Word; newBalance: UInt64;
  newN_operation: Cardinal);
Var
    iblock: Cardinal;
    i, j, iAccount: Integer;
    lastbalance: UInt64;
    acc: TAccount;
    bacc: TBlockAccount;
    P: PBlockAccount;
begin
    iblock := account_number DIV CT_AccountsPerBlock;
    iAccount := account_number MOD CT_AccountsPerBlock;
    acc := account(account_number);
    P := FBlockAccountsList.Items[iblock];

    if (NOT TAccountComp.EqualAccountKeys(acc.accountInfo.accountKey, newAccountInfo.accountKey)) then
    begin
        AccountKeyListRemoveAccount(acc.accountInfo.accountKey, [account_number]);
        AccountKeyListAddAccounts(newAccountInfo.accountKey, [account_number]);
    end;

    acc.accountInfo := newAccountInfo;
    // Name:
    If acc.name <> newName then
    begin
        If acc.name <> '' then
        begin
            i := FOrderedByName.IndexOf(acc.name);
            if i < 0 then
                TLog.NewLog(lterror, Classname, 'ERROR DEV 20170606-1')
            else
                FOrderedByName.Delete(i);
        end;
        acc.name := newName;
        If acc.name <> '' then
        begin
            i := FOrderedByName.IndexOf(acc.name);
            if i >= 0 then
                TLog.NewLog(lterror, Classname, 'ERROR DEV 20170606-2')
            else
                FOrderedByName.Add(acc.name, account_number);
        end;
    end;
    acc.account_type := newType;
    lastbalance := acc.balance;
    acc.balance := newBalance;
    // Will update previous_updated_block only on first time/block
    If acc.updated_block <> blocksCount then
    begin
        acc.previous_updated_block := acc.updated_block;
        acc.updated_block := blocksCount;
    end;
    acc.n_operation := newN_operation;
    // Save new account values
    ToTMemAccount(acc, P^.accounts[iAccount]);
    // Update block_hash
    bacc := block(iblock);

{$IFDEF uselowmem}
    TBaseType.To32Bytes(CalcBlockHash(bacc, FCurrentProtocol >= CT_PROTOCOL_2), P^.block_hash);
{$ELSE}
    P^.block_hash := CalcBlockHash(bacc, FCurrentProtocol >= CT_PROTOCOL_2);
{$ENDIF}
    // Update buffer block hash
    j := (length(P^.block_hash) * (iblock));
    for i := 1 to length(P^.block_hash) do
    begin
{$IFDEF FPC}
        FBufferBlocksHash[i + j] := AnsiChar(P^.block_hash[i - (low(FBufferBlocksHash) - low(P^.block_hash))]);
{$ELSE}
        FBufferBlocksHash[i + j] := AnsiChar(P^.block_hash[i - {$IFDEF uselowmem}1{$ELSE}0{$ENDIF}]);
{$ENDIF}
    end;

    FTotalBalance := FTotalBalance - (Int64(lastbalance) - Int64(newBalance));
    FTotalFee := FTotalFee + (Int64(lastbalance) - Int64(newBalance));
end;

procedure TPCSafeBox.StartThreadSafe;
begin
    TPCThread.ProtectEnterCriticalSection(Self, FLock);
end;

{ TPCSafeBoxTransaction }

function TPCSafeBoxTransaction.account(account_number: Cardinal): TAccount;
Var
    i: Integer;
begin
    if FOrderedList.Find(account_number, i) then
        Result := PAccount(FOrderedList.FList[i])^
    else
    begin
        Result := FreezedSafeBox.account(account_number);
    end;
end;

function TPCSafeBoxTransaction.BuyAccount(buyer, account_to_buy, seller: Cardinal; n_operation: Cardinal; amount, account_price, fee: UInt64;
  const new_account_key: TAccountKey; var errors: AnsiString): Boolean;
Var
    PaccBuyer, PaccAccountToBuy, PaccSeller: PAccount;
begin
    Result := false;
    errors := '';
    if not CheckIntegrity then
    begin
        errors := 'Invalid integrity in accounts transaction';
        exit;
    end;
    if (buyer < 0) Or (buyer >= (FFreezedAccounts.blocksCount * CT_AccountsPerBlock)) Or (account_to_buy < 0) Or
      (account_to_buy >= (FFreezedAccounts.blocksCount * CT_AccountsPerBlock)) Or (seller < 0) Or
      (seller >= (FFreezedAccounts.blocksCount * CT_AccountsPerBlock)) then
    begin
        errors := 'Invalid account number on buy';
        exit;
    end;
    if TAccountComp.IsAccountBlockedByProtocol(buyer, FFreezedAccounts.blocksCount) then
    begin
        errors := 'Buyer account is blocked for protocol';
        exit;
    end;
    if TAccountComp.IsAccountBlockedByProtocol(account_to_buy, FFreezedAccounts.blocksCount) then
    begin
        errors := 'Account to buy is blocked for protocol';
        exit;
    end;
    if TAccountComp.IsAccountBlockedByProtocol(seller, FFreezedAccounts.blocksCount) then
    begin
        errors := 'Seller account is blocked for protocol';
        exit;
    end;
    PaccBuyer := GetInternalAccount(buyer);
    PaccAccountToBuy := GetInternalAccount(account_to_buy);
    PaccSeller := GetInternalAccount(seller);
    if (PaccBuyer^.n_operation + 1 <> n_operation) then
    begin
        errors := 'Incorrect n_operation';
        exit;
    end;
    if (PaccBuyer^.balance < (amount + fee)) then
    begin
        errors := 'Insuficient founds';
        exit;
    end;
    if (fee > CT_MaxTransactionFee) then
    begin
        errors := 'Max fee';
        exit;
    end;
    if (TAccountComp.IsAccountLocked(PaccBuyer^.accountInfo, FFreezedAccounts.blocksCount)) then
    begin
        errors := 'Buyer account is locked until block ' + inttostr(PaccBuyer^.accountInfo.locked_until_block);
        exit;
    end;
    If not(TAccountComp.IsAccountForSale(PaccAccountToBuy^.accountInfo)) then
    begin
        errors := 'Account is not for sale';
        exit;
    end;
    if (PaccAccountToBuy^.accountInfo.new_publicKey.EC_OpenSSL_NID <> CT_TECDSA_Public_Nul.EC_OpenSSL_NID) And
      (Not TAccountComp.EqualAccountKeys(PaccAccountToBuy^.accountInfo.new_publicKey, new_account_key)) then
    begin
        errors := 'New public key is not equal to allowed new public key for account';
        exit;
    end;
    // Buy an account applies when account_to_buy.amount + operation amount >= price
    // Then, account_to_buy.amount will be (account_to_buy.amount + amount - price)
    // and buyer.amount will be buyer.amount + price
    if (PaccAccountToBuy^.accountInfo.price > (PaccAccountToBuy^.balance + amount)) then
    begin
        errors := 'Account price ' + TAccountComp.FormatMoney(PaccAccountToBuy^.accountInfo.price) + ' < balance ' +
          TAccountComp.FormatMoney(PaccAccountToBuy^.balance) + ' + amount ' + TAccountComp.FormatMoney(amount);
        exit;
    end;

    If PaccBuyer^.updated_block <> FFreezedAccounts.blocksCount then
    begin
        PaccBuyer^.previous_updated_block := PaccBuyer^.updated_block;
        PaccBuyer^.updated_block := FFreezedAccounts.blocksCount;
    end;

    If PaccAccountToBuy^.updated_block <> FFreezedAccounts.blocksCount then
    begin
        PaccAccountToBuy^.previous_updated_block := PaccAccountToBuy^.updated_block;
        PaccAccountToBuy^.updated_block := FFreezedAccounts.blocksCount;
    end;

    If PaccSeller^.updated_block <> FFreezedAccounts.blocksCount then
    begin
        PaccSeller^.previous_updated_block := PaccSeller^.updated_block;
        PaccSeller^.updated_block := FFreezedAccounts.blocksCount;
    end;

    // Inc buyer n_operation
    PaccBuyer^.n_operation := n_operation;
    // Set new balance values
    PaccBuyer^.balance := PaccBuyer^.balance - (amount + fee);
    PaccAccountToBuy^.balance := PaccAccountToBuy^.balance + amount - PaccAccountToBuy^.accountInfo.price;
    PaccSeller^.balance := PaccSeller^.balance + PaccAccountToBuy^.accountInfo.price;

    // After buy, account will be unlocked and set to normal state and new account public key changed
    PaccAccountToBuy^.accountInfo := CT_AccountInfo_NUL;
    PaccAccountToBuy^.accountInfo.state := as_Normal;
    PaccAccountToBuy^.accountInfo.accountKey := new_account_key;

    Dec(FTotalBalance, fee);
    inc(FTotalFee, fee);
    Result := true;
end;

function TPCSafeBoxTransaction.CheckIntegrity: Boolean;
begin
    Result := FOldSafeBoxHash = FFreezedAccounts.FSafeBoxHash;
end;

procedure TPCSafeBoxTransaction.CleanTransaction;
begin
    FOrderedList.Clear;
    FOldSafeBoxHash := FFreezedAccounts.FSafeBoxHash;
    FTotalBalance := FFreezedAccounts.FTotalBalance;
    FTotalFee := 0;
    FAccountNames_Added.Clear;
    FAccountNames_Deleted.Clear;
end;

function TPCSafeBoxTransaction.Commit(const operationBlock: TOperationBlock; var errors: AnsiString): Boolean;
Var
    i, j: Integer;
    b: TBlockAccount;
    Pa: PAccount;
begin
    Result := false;
    errors := '';
    FFreezedAccounts.StartThreadSafe;
    try
        if not CheckIntegrity then
        begin
            errors := 'Invalid integrity in accounts transaction on commit';
            exit;
        end;
        for i := 0 to FOrderedList.FList.Count - 1 do
        begin
            Pa := PAccount(FOrderedList.FList[i]);
            FFreezedAccounts.SetAccount(Pa^.account, Pa^.accountInfo, Pa^.name, Pa^.account_type, Pa^.balance, Pa^.n_operation);
        end;
        //
        if (FFreezedAccounts.TotalBalance <> FTotalBalance) then
        begin
            TLog.NewLog(lterror, Classname, Format('Invalid integrity balance! StrongBox:%d Transaction:%d', [FFreezedAccounts.TotalBalance, FTotalBalance]));
        end;
        if (FFreezedAccounts.FTotalFee <> FTotalFee) then
        begin
            TLog.NewLog(lterror, Classname, Format('Invalid integrity fee! StrongBox:%d Transaction:%d', [FFreezedAccounts.FTotalFee, FTotalFee]));
        end;
        b := FFreezedAccounts.AddNew(operationBlock);
        if (b.accounts[0].balance <> (operationBlock.reward + FTotalFee)) then
        begin
            TLog.NewLog(lterror, Classname, Format('Invalid integrity reward! Account:%d Balance:%d  Reward:%d Fee:%d (Reward+Fee:%d)',
              [b.accounts[0].account, b.accounts[0].balance, operationBlock.reward, FTotalFee, operationBlock.reward + FTotalFee]));
        end;
        CleanTransaction;
        //
        if (FFreezedAccounts.FCurrentProtocol < CT_PROTOCOL_2) And (operationBlock.protocol_version = CT_PROTOCOL_2) then
        begin
            // First block with new protocol!
            if FFreezedAccounts.CanUpgradeToProtocol2 then
            begin
                TLog.NewLog(ltInfo, Classname, 'Protocol upgrade to v2');
                If not FFreezedAccounts.DoUpgradeToProtocol2 then
                begin
                    raise Exception.Create('Cannot upgrade to protocol v2 !');
                end;
            end;
        end;
        Result := true;
    finally
        FFreezedAccounts.EndThreadSave;
    end;
end;

procedure TPCSafeBoxTransaction.CopyFrom(transaction: TPCSafeBoxTransaction);
Var
    i: Integer;
    P: PAccount;
begin
    if transaction = Self then
        exit;
    if transaction.FFreezedAccounts <> FFreezedAccounts then
        raise Exception.Create('Invalid Freezed accounts to copy');
    CleanTransaction;
    for i := 0 to transaction.FOrderedList.FList.Count - 1 do
    begin
        P := PAccount(transaction.FOrderedList.FList[i]);
        FOrderedList.Add(P^);
    end;
    FOldSafeBoxHash := transaction.FOldSafeBoxHash;
    FTotalBalance := transaction.FTotalBalance;
    FTotalFee := transaction.FTotalFee;
end;

constructor TPCSafeBoxTransaction.Create(SafeBox: TPCSafeBox);
begin
    FOrderedList := TOrderedAccountList.Create;
    FFreezedAccounts := SafeBox;
    FOldSafeBoxHash := SafeBox.FSafeBoxHash;
    FTotalBalance := FFreezedAccounts.FTotalBalance;
    FTotalFee := 0;
    FAccountNames_Added := TOrderedRawList.Create;
    FAccountNames_Deleted := TOrderedRawList.Create;
end;

destructor TPCSafeBoxTransaction.Destroy;
begin
    CleanTransaction;
    FreeAndNil(FOrderedList);
    FreeAndNil(FAccountNames_Added);
    FreeAndNil(FAccountNames_Deleted);
    inherited;
end;

function TPCSafeBoxTransaction.GetInternalAccount(account_number: Cardinal): PAccount;
Var
    i: Integer;
    P: PAccount;
begin
    if FOrderedList.Find(account_number, i) then
        Result := PAccount(FOrderedList.FList[i])
    else
    begin
        i := FOrderedList.Add(FreezedSafeBox.account(account_number));
        Result := PAccount(FOrderedList.FList[i]);
    end;
end;

function TPCSafeBoxTransaction.Modified(index: Integer): TAccount;
begin
    Result := FOrderedList.Get(index);
end;

function TPCSafeBoxTransaction.ModifiedCount: Integer;
begin
    Result := FOrderedList.Count;
end;

procedure TPCSafeBoxTransaction.Rollback;
begin
    CleanTransaction;
end;

function TPCSafeBoxTransaction.TransferAmount(Sender, target: Cardinal; n_operation: Cardinal; amount, fee: UInt64; var errors: AnsiString): Boolean;
Var
    intSender, intTarget: Integer;
    PaccSender, PaccTarget: PAccount;
begin
    Result := false;
    errors := '';
    if not CheckIntegrity then
    begin
        errors := 'Invalid integrity in accounts transaction';
        exit;
    end;
    if (Sender < 0) Or (Sender >= (FFreezedAccounts.blocksCount * CT_AccountsPerBlock)) Or (target < 0) Or
      (target >= (FFreezedAccounts.blocksCount * CT_AccountsPerBlock)) then
    begin
        errors := 'Invalid sender or target on transfer';
        exit;
    end;
    if TAccountComp.IsAccountBlockedByProtocol(Sender, FFreezedAccounts.blocksCount) then
    begin
        errors := 'Sender account is blocked for protocol';
        exit;
    end;
    if TAccountComp.IsAccountBlockedByProtocol(target, FFreezedAccounts.blocksCount) then
    begin
        errors := 'Target account is blocked for protocol';
        exit;
    end;
    PaccSender := GetInternalAccount(Sender);
    PaccTarget := GetInternalAccount(target);
    if (PaccSender^.n_operation + 1 <> n_operation) then
    begin
        errors := 'Incorrect n_operation';
        exit;
    end;
    if (PaccSender^.balance < (amount + fee)) then
    begin
        errors := 'Insuficient founds';
        exit;
    end;
    if ((PaccTarget^.balance + amount) > CT_MaxWalletAmount) then
    begin
        errors := 'Max account balance';
        exit;
    end;
    if (fee > CT_MaxTransactionFee) then
    begin
        errors := 'Max fee';
        exit;
    end;
    if (TAccountComp.IsAccountLocked(PaccSender^.accountInfo, FFreezedAccounts.blocksCount)) then
    begin
        errors := 'Sender account is locked until block ' + inttostr(PaccSender^.accountInfo.locked_until_block);
        exit;
    end;

    If PaccSender^.updated_block <> FFreezedAccounts.blocksCount then
    begin
        PaccSender^.previous_updated_block := PaccSender^.updated_block;
        PaccSender^.updated_block := FFreezedAccounts.blocksCount;
    end;

    If PaccTarget^.updated_block <> FFreezedAccounts.blocksCount then
    begin
        PaccTarget^.previous_updated_block := PaccTarget.updated_block;
        PaccTarget^.updated_block := FFreezedAccounts.blocksCount;
    end;

    PaccSender^.n_operation := n_operation;
    PaccSender^.balance := PaccSender^.balance - (amount + fee);
    PaccTarget^.balance := PaccTarget^.balance + (amount);

    Dec(FTotalBalance, fee);
    inc(FTotalFee, fee);
    Result := true;
end;

function TPCSafeBoxTransaction.UpdateAccountInfo(signer_account, signer_n_operation, target_account: Cardinal; accountInfo: TAccountInfo; newName: TRawBytes;
  newType: Word; fee: UInt64; var errors: AnsiString): Boolean;
Var
    i: Integer;
    P_signer, P_target: PAccount;
begin
    Result := false;
    errors := '';
    if (signer_account < 0) Or (signer_account >= (FFreezedAccounts.blocksCount * CT_AccountsPerBlock)) Or (target_account < 0) Or
      (target_account >= (FFreezedAccounts.blocksCount * CT_AccountsPerBlock)) Then
    begin
        errors := 'Invalid account';
        exit;
    end;
    if (TAccountComp.IsAccountBlockedByProtocol(signer_account, FFreezedAccounts.blocksCount)) Or
      (TAccountComp.IsAccountBlockedByProtocol(target_account, FFreezedAccounts.blocksCount)) then
    begin
        errors := 'account is blocked for protocol';
        exit;
    end;
    P_signer := GetInternalAccount(signer_account);
    P_target := GetInternalAccount(target_account);
    if (P_signer^.n_operation + 1 <> signer_n_operation) then
    begin
        errors := 'Incorrect n_operation';
        exit;
    end;
    if (P_signer^.balance < fee) then
    begin
        errors := 'Insuficient founds';
        exit;
    end;
    if (TAccountComp.IsAccountLocked(P_signer^.accountInfo, FFreezedAccounts.blocksCount)) then
    begin
        errors := 'Signer account is locked until block ' + inttostr(P_signer^.accountInfo.locked_until_block);
        exit;
    end;
    if (TAccountComp.IsAccountLocked(P_target^.accountInfo, FFreezedAccounts.blocksCount)) then
    begin
        errors := 'Target account is locked until block ' + inttostr(P_target^.accountInfo.locked_until_block);
        exit;
    end;
    if P_signer^.updated_block <> FFreezedAccounts.blocksCount then
    begin
        P_signer^.previous_updated_block := P_signer^.updated_block;
        P_signer^.updated_block := FFreezedAccounts.blocksCount;
    end;
    if (signer_account <> target_account) then
    begin
        if P_target^.updated_block <> FFreezedAccounts.blocksCount then
        begin
            P_target^.previous_updated_block := P_target^.updated_block;
            P_target^.updated_block := FFreezedAccounts.blocksCount;
        end;
    end;
    if Not TAccountComp.EqualAccountKeys(P_signer^.accountInfo.accountKey, P_target^.accountInfo.accountKey) then
    begin
        errors := 'Signer and target have diff key';
        exit;
    end;
    if (newName <> P_target^.name) then
    begin
        // NEW NAME CHANGE CHECK:
        if (newName <> '') then
        begin
            If Not FFreezedAccounts.ValidAccountName(newName, errors) then
            begin
                errors := 'Invalid account name "' + newName + '" length:' + inttostr(length(newName)) + ': ' + errors;
                exit;
            end;
            i := FFreezedAccounts.FindAccountByName(newName);
            if (i >= 0) then
            begin
                // This account name is in the safebox... check if deleted:
                i := FAccountNames_Deleted.IndexOf(newName);
                if i < 0 then
                begin
                    errors := 'Account name "' + newName + '" is in current use';
                    exit;
                end;
            end;
            i := FAccountNames_Added.IndexOf(newName);
            if (i >= 0) then
            begin
                // This account name is added in this transaction! (perhaps deleted also, but does not allow to "double add same name in same block")
                errors := 'Account name "' + newName + '" is in same transaction';
                exit;
            end;
        end;
        // Ok, include
        if (P_target^.name <> '') then
        begin
            // In use in the safebox, mark as deleted
            FAccountNames_Deleted.Add(P_target^.name, target_account);
        end;
        if (newName <> '') then
        begin
            FAccountNames_Added.Add(newName, target_account);
        end;
    end;

    P_signer^.n_operation := signer_n_operation;
    P_target^.accountInfo := accountInfo;
    P_target^.name := newName;
    P_target^.account_type := newType;
    Dec(P_signer^.balance, fee); // Signer is who pays the fee
    Dec(FTotalBalance, fee);
    inc(FTotalFee, fee);
    Result := true;
end;

{ TOrderedAccountList }

Function TOrderedAccountList.Add(const account: TAccount): Integer;
Var
    P: PAccount;
begin
    if Find(account.account, Result) then
    begin
        PAccount(FList[Result])^ := account;
    end
    else
    begin
        New(P);
        P^ := account;
        FList.Insert(Result, P);
    end;
end;

procedure TOrderedAccountList.Clear;
Var
    i: Integer;
    P: PAccount;
begin
    for i := 0 to FList.Count - 1 do
    begin
        P := FList[i];
        Dispose(P);
    end;
    FList.Clear;
end;

function TOrderedAccountList.Count: Integer;
begin
    Result := FList.Count;
end;

constructor TOrderedAccountList.Create;
begin
    FList := TList.Create;
end;

destructor TOrderedAccountList.Destroy;
begin
    Clear;
    FreeAndNil(FList);
    inherited;
end;

function TOrderedAccountList.Find(const account_number: Cardinal; var index: Integer): Boolean;
var
    l, H, i: Integer;
    c: Int64;
begin
    Result := false;
    l := 0;
    H := FList.Count - 1;
    while l <= H do
    begin
        i := (l + H) shr 1;
        c := Int64(PAccount(FList[i]).account) - Int64(account_number);
        if c < 0 then
            l := i + 1
        else
        begin
            H := i - 1;
            if c = 0 then
            begin
                Result := true;
                l := i;
            end;
        end;
    end;
    Index := l;
end;

function TOrderedAccountList.Get(index: Integer): TAccount;
begin
    Result := PAccount(FList.Items[index])^;
end;

{ TOrderedAccountKeysList }
Type
    TOrderedAccountKeyList = Record
        rawaccountkey: TRawBytes;
        accounts_number: TOrderedCardinalList;
    end;

    POrderedAccountKeyList = ^TOrderedAccountKeyList;

function SortOrdered(Item1, Item2: Pointer): Integer;
begin
    Result := PtrInt(Item1) - PtrInt(Item2);
end;

procedure TOrderedAccountKeysList.AddAccountKey(const accountKey: TAccountKey);
Var
    P: POrderedAccountKeyList;
    i, j: Integer;
begin
    if Not Find(accountKey, i) then
    begin
        New(P);
        P^.rawaccountkey := TAccountComp.AccountKey2RawString(accountKey);
        P^.accounts_number := TOrderedCardinalList.Create;
        FOrderedAccountKeysList.Insert(i, P);
        // Search this key in the AccountsList and add all...
        j := 0;
        if Assigned(FAccountList) then
        begin
            For i := 0 to FAccountList.AccountsCount - 1 do
            begin
                If TAccountComp.EqualAccountKeys(FAccountList.account(i).accountInfo.accountKey, accountKey) then
                begin
                    // Note: P^.accounts will be ascending ordered due to "for i:=0 to ..."
                    P^.accounts_number.Add(i);
                end;
            end;
            TLog.NewLog(ltDebug, Classname, Format('Adding account key (%d of %d) %s', [j, FAccountList.AccountsCount,
              TCrypto.ToHexaString(TAccountComp.AccountKey2RawString(accountKey))]));
        end
        else
        begin
            TLog.NewLog(ltDebug, Classname, Format('Adding account key (no Account List) %s',
              [TCrypto.ToHexaString(TAccountComp.AccountKey2RawString(accountKey))]));
        end;
    end;
end;

procedure TOrderedAccountKeysList.AddAccounts(const accountKey: TAccountKey; const accounts: array of Cardinal);
Var
    P: POrderedAccountKeyList;
    i, i2: Integer;
begin
    if Find(accountKey, i) then
    begin
        P := POrderedAccountKeyList(FOrderedAccountKeysList[i]);
    end
    else if (FAutoAddAll) then
    begin
        New(P);
        P^.rawaccountkey := TAccountComp.AccountKey2RawString(accountKey);
        P^.accounts_number := TOrderedCardinalList.Create;
        FOrderedAccountKeysList.Insert(i, P);
    end
    else
        exit;
    for i := Low(accounts) to High(accounts) do
    begin
        P^.accounts_number.Add(accounts[i]);
    end;
end;

procedure TOrderedAccountKeysList.Clear;
begin
    ClearAccounts(true);
end;

procedure TOrderedAccountKeysList.ClearAccounts(RemoveAccountList: Boolean);
Var
    P: POrderedAccountKeyList;
    i: Integer;
begin
    for i := 0 to FOrderedAccountKeysList.Count - 1 do
    begin
        P := FOrderedAccountKeysList[i];
        if RemoveAccountList then
        begin
            P^.accounts_number.Free;
            Dispose(P);
        end
        else
        begin
            P^.accounts_number.Clear;
        end;
    end;
    if RemoveAccountList then
    begin
        FOrderedAccountKeysList.Clear;
    end;
end;

function TOrderedAccountKeysList.Count: Integer;
begin
    Result := FOrderedAccountKeysList.Count;
end;

constructor TOrderedAccountKeysList.Create(AccountList: TPCSafeBox; AutoAddAll: Boolean);
Var
    i: Integer;
begin
    TLog.NewLog(ltDebug, Classname, 'Creating an Ordered Account Keys List adding all:' + CT_TRUE_FALSE[AutoAddAll]);
    FAutoAddAll := AutoAddAll;
    FAccountList := AccountList;
    FOrderedAccountKeysList := TList.Create;
    if Assigned(AccountList) then
    begin
        AccountList.FListOfOrderedAccountKeysList.Add(Self);
        if AutoAddAll then
        begin
            for i := 0 to AccountList.AccountsCount - 1 do
            begin
                AddAccountKey(AccountList.account(i).accountInfo.accountKey);
            end;
        end;
    end;
end;

destructor TOrderedAccountKeysList.Destroy;
begin
    TLog.NewLog(ltDebug, Classname, 'Destroying an Ordered Account Keys List adding all:' + CT_TRUE_FALSE[FAutoAddAll]);
    if Assigned(FAccountList) then
    begin
        FAccountList.FListOfOrderedAccountKeysList.Remove(Self);
    end;
    ClearAccounts(true);
    FreeAndNil(FOrderedAccountKeysList);
    inherited;
end;

function TOrderedAccountKeysList.Find(const accountKey: TAccountKey; var index: Integer): Boolean;
var
    l, H, i, c: Integer;
    rak: TRawBytes;
begin
    Result := false;
    rak := TAccountComp.AccountKey2RawString(accountKey);
    l := 0;
    H := FOrderedAccountKeysList.Count - 1;
    while l <= H do
    begin
        i := (l + H) shr 1;
        c := CompareStr(POrderedAccountKeyList(FOrderedAccountKeysList[i]).rawaccountkey, rak);
        if c < 0 then
            l := i + 1
        else
        begin
            H := i - 1;
            if c = 0 then
            begin
                Result := true;
                l := i;
            end;
        end;
    end;
    Index := l;
end;

function TOrderedAccountKeysList.GetAccountKey(index: Integer): TAccountKey;
Var
    raw: TRawBytes;
begin
    raw := POrderedAccountKeyList(FOrderedAccountKeysList[index]).rawaccountkey;
    Result := TAccountComp.RawString2Accountkey(raw);
end;

function TOrderedAccountKeysList.GetAccountKeyList(index: Integer): TOrderedCardinalList;
begin
    Result := POrderedAccountKeyList(FOrderedAccountKeysList[index]).accounts_number;
end;

function TOrderedAccountKeysList.IndexOfAccountKey(const accountKey: TAccountKey): Integer;
begin
    If Not Find(accountKey, Result) then
        Result := -1;
end;

procedure TOrderedAccountKeysList.RemoveAccounts(const accountKey: TAccountKey; const accounts: array of Cardinal);
Var
    P: POrderedAccountKeyList;
    i, j: Integer;
begin
    if Not Find(accountKey, i) then
        exit; // Nothing to do
    P := POrderedAccountKeyList(FOrderedAccountKeysList[i]);
    for j := Low(accounts) to High(accounts) do
    begin
        P^.accounts_number.Remove(accounts[j]);
    end;
    if (P^.accounts_number.Count = 0) And (FAutoAddAll) then
    begin
        // Remove from list
        FOrderedAccountKeysList.Delete(i);
        // Free it
        P^.accounts_number.Free;
        Dispose(P);
    end;
end;

procedure TOrderedAccountKeysList.RemoveAccountKey(const accountKey: TAccountKey);
Var
    P: POrderedAccountKeyList;
    i, j: Integer;
begin
    if Not Find(accountKey, i) then
        exit; // Nothing to do
    P := POrderedAccountKeyList(FOrderedAccountKeysList[i]);
    // Remove from list
    FOrderedAccountKeysList.Delete(i);
    // Free it
    P^.accounts_number.Free;
    Dispose(P);
end;

{ TOrderedCardinalList }

function TOrderedCardinalList.Add(Value: Cardinal): Integer;
begin
    if Find(Value, Result) then
        exit
    else
    begin
        FOrderedList.Insert(Result, TObject(Value));
        NotifyChanged;
    end;
end;

procedure TOrderedCardinalList.Clear;
begin
    FOrderedList.Clear;
    NotifyChanged;
end;

procedure TOrderedCardinalList.CopyFrom(Sender: TOrderedCardinalList);
Var
    i: Integer;
begin
    if Self = Sender then
        exit;
    Disable;
    Try
        Clear;
        for i := 0 to Sender.Count - 1 do
        begin
            Add(Sender.Get(i));
        end;
    Finally
        Enable;
    End;
end;

function TOrderedCardinalList.Count: Integer;
begin
    Result := FOrderedList.Count;
end;

constructor TOrderedCardinalList.Create;
begin
    FOrderedList := TList.Create;
    FDisabledsCount := 0;
    FModifiedWhileDisabled := false;
end;

destructor TOrderedCardinalList.Destroy;
begin
    FOrderedList.Free;
    inherited;
end;

procedure TOrderedCardinalList.Disable;
begin
    inc(FDisabledsCount);
end;

procedure TOrderedCardinalList.Enable;
begin
    if FDisabledsCount <= 0 then
        raise Exception.Create('Dev error. Invalid disabled counter');
    Dec(FDisabledsCount);
    if (FDisabledsCount = 0) And (FModifiedWhileDisabled) then
        NotifyChanged;
end;

function TOrderedCardinalList.Find(const Value: Cardinal; var index: Integer): Boolean;
var
    l, H, i: Integer;
    c: Int64;
begin
    Result := false;
    l := 0;
    H := FOrderedList.Count - 1;
    while l <= H do
    begin
        i := (l + H) shr 1;
        c := Int64(FOrderedList[i]) - Int64(Value);
        if c < 0 then
            l := i + 1
        else
        begin
            H := i - 1;
            if c = 0 then
            begin
                Result := true;
                l := i;
            end;
        end;
    end;
    Index := l;
end;

function TOrderedCardinalList.Get(index: Integer): Cardinal;
begin
    Result := Cardinal(FOrderedList[index]);
end;

procedure TOrderedCardinalList.NotifyChanged;
begin
    if FDisabledsCount > 0 then
    begin
        FModifiedWhileDisabled := true;
        exit;
    end;
    FModifiedWhileDisabled := false;
    if Assigned(FOnListChanged) then
        FOnListChanged(Self);
end;

procedure TOrderedCardinalList.Remove(Value: Cardinal);
Var
    i: Integer;
begin
    if Find(Value, i) then
    begin
        FOrderedList.Delete(i);
        NotifyChanged;
    end;
end;

Function TOrderedCardinalList.ToArray: TCardinalsArray;
var
    i: Integer;
begin
    SetLength(Result, Self.Count);
    for i := 0 to Self.Count - 1 do
        Result[i] := Self.Get(i);
end;

{ TOrderedRawList }

Type
    TRawListData = Record
        RawData: TRawBytes;
        tag: Integer;
    End;

    PRawListData = ^TRawListData;

function TOrderedRawList.Add(const RawData: TRawBytes; tagValue: Integer = 0): Integer;
Var
    P: PRawListData;
begin
    if Find(RawData, Result) then
    begin
        PRawListData(FList[Result])^.tag := tagValue;
    end
    else
    begin
        New(P);
        P^.RawData := RawData;
        P^.tag := tagValue;
        FList.Insert(Result, P);
    end;
end;

procedure TOrderedRawList.Clear;
Var
    P: PRawListData;
    i: Integer;
begin
    for i := FList.Count - 1 downto 0 do
    begin
        P := FList[i];
        Dispose(P);
    end;
    FList.Clear;
end;

function TOrderedRawList.Count: Integer;
begin
    Result := FList.Count;
end;

constructor TOrderedRawList.Create;
begin
    FList := TList.Create;
end;

procedure TOrderedRawList.Delete(index: Integer);
Var
    P: PRawListData;
begin
    P := PRawListData(FList[index]);
    FList.Delete(index);
    Dispose(P);
end;

destructor TOrderedRawList.Destroy;
begin
    Clear;
    FreeAndNil(FList);
    inherited;
end;

function TOrderedRawList.Find(const RawData: TRawBytes; var index: Integer): Boolean;
var
    l, H, i: Integer;
    c: Integer;
begin
    Result := false;
    l := 0;
    H := FList.Count - 1;
    while l <= H do
    begin
        i := (l + H) shr 1;
        c := BinStrComp(PRawListData(FList[i])^.RawData, RawData);
        if c < 0 then
            l := i + 1
        else
        begin
            H := i - 1;
            if c = 0 then
            begin
                Result := true;
                l := i;
            end;
        end;
    end;
    Index := l;
end;

function TOrderedRawList.Get(index: Integer): TRawBytes;
begin
    Result := PRawListData(FList[index])^.RawData;
end;

function TOrderedRawList.GetTag(index: Integer): Integer;
begin
    Result := PRawListData(FList[index])^.tag;
end;

function TOrderedRawList.GetTag(const RawData: TRawBytes): Integer;
Var
    i: Integer;
begin
    if Not Find(RawData, i) then
    begin
        Result := 0;
    end
    else
    begin
        Result := PRawListData(FList[i])^.tag;
    end;
end;

function TOrderedRawList.IndexOf(const RawData: TRawBytes): Integer;
begin
    if Not Find(RawData, Result) then
        Result := -1;
end;

procedure TOrderedRawList.SetTag(const RawData: TRawBytes; newTagValue: Integer);
begin
    Add(RawData, newTagValue);
end;

end.
