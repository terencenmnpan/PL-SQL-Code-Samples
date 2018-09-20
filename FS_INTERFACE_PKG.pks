CREATE OR REPLACE PACKAGE CARSUSR.FS_INTERFACE_PKG AS
/******************************************************************************
   NAME:       FS_INTERFACE_PKG
   PURPOSE:

   REVISIONS:
   Ver        Date        Author           Description
   ---------  ----------  ---------------  ------------------------------------
   1.0        01/19/2018  Vinaykumar Patil 1. Created for Financial Information System of California Interface
                                              Added Functions and Procedures
                                           2. EXTRACT_INFAR006_DATA Function
                                           3. INSERT_INFAR006_DATA Procedure
                                           4. INSERT_INFAR001_DATA Procedure
             02/05/2018  Vinaykumar Patil  1. Added the Array Counter 
                                           2. GET_INFAR006_COUNTER_DATA
             02/08/2018  Vinaykumar Patil  1. Added procedure UPD_INFAR006_COUNTER_DATA
                                           2. Added procedure UPD_INFAR001_COUNTER_DATA
             02/09/2018  Christina Nguyen  1. Added INFAR006 Cursor Data Type
                                           2. Added INFAR006 Functions 
             02/11/2018  Vinaykumar Patil  1. Added procedure UPD_INFAR001_HEADER_DATA  
             02/12/2018  Christina Nguyen  1. Added procedure GET_INFAR006_DATA 
             02/21/2018  Christina Nguyen  1. Added procedure UPDATE_ACCTG_ENTRY_STATUS
             02/23/2018  Christina Nguyen  1. Added procedure UPDATE_STATUS_BY_ID
                                           2. Added procedure FS_BATCH_HEADER
             02/24/2018  Christina Nguyen  1. Added function FS_BATCH_TRIAL_RUN
                                           2. Added procedure FS_BATCH_DRIVER 
             02/25/2018  Christina Nguyen  1. Fixed GET_INFAR006_COUNTER_DATA logic in
                                              GET_INFAR006_DATA.
             02/26/2018  Christina Nguyen  1. Renamed INSERT_INFAR006_DATA1 to     
                                              INSERT_INFAR006_DATA
                                           2. Added function GET_FS_LINE_NUMBER
                                           3. Added function GET_FS_ITEM_LINE
                                           4. Fixed Incorrect LINE and ITEM_LINE
                                              for INFAR006
             02/27/2018  Christina Nguyen  1. Fixed function GET_FS_AS_OF_DATE
             02/27/2018  Terence Pan       1. Added GET_INFAR001_DATA
             02/28/2018  Christina Nguyen  1. Changed P_EVENT_TYPE_CODE from GET_INFAR006_DATA
                                              from EVENT_TYPE.EVENT_TYPE_CODE%TYPE to VARCHAR2 
                                              to handle multiple event type codes
                                           2. Populated Collector value for CALOSHA
                                           3. Populated CHARTFIELD1 if FUND_DETAIL
                                              has value.
                                           4. Added ACCOUNTING_TRANSACTION.DAILY_POSTING_DATE
                                              criteria in procedure UPDATE_ACCTG_ENTRY_STATUS
                                              for INFAR006 gathering data from last batch process date
                                           5. Cleaned up
            03/03/2018  Vinaykumar Patil   1. Added the LOG_CARS_ERROR procedure
            03/15/2018  Vinay Patil        1. INFAR001 has FS_ROW_ID column usage and added constants
            04/04/2018  Terence Pan        1. Added function UPD_INFAR006_ZERO_BAL to check for zero balance
            05/01/2018  Vinay Patil        1. Added Log message to CARS ERROR LOG table in CARS schem in FS_BATCH_DRIVE procedure
                                           2. Added error severity constants
            05/11/2018  Christina Nguyen   1. Removed c_EVENT_020
                                           2. Added AR Others Payment Reversal Events
                                           3. Added IS_REVERSAL_EVENT function.
            05/11/2018  Vinay Patil        1. Added function FUNC_GET_FISCAL_MONTH, FUNC_GET_FISCAL_YEAR and FUNC_GET_PRIOR_FISCAL_YEAR
            05/16/2018  Christina Nguyen   1. Added UPD_EVENT_900_STATUS to set Status NEW to Status NOT_TRANSMITTED
            05/18/2018  Terence Pan        1. Added constants for GET_FS_GL_REV_SRC to handle reclass and write off
            06/01/2018  Vinay Patil        1. Modified logic for INFAR001 Insert procedure to accept and populate AR_ROOT_DOCUMENT
*****************************************************************************/

c_YES                   CONSTANT VARCHAR2(1)                                        := 'Y';
c_NO                    CONSTANT VARCHAR2(1)                                        := 'N';

c_ADD_COUNTER           CONSTANT VARCHAR2(15)                                       := 'ADD';
c_EMPTY_COUNTER         CONSTANT VARCHAR2(15)                                       := 'EMPTY_COUNTER';
c_DELETE_LAST           CONSTANT VARCHAR2(15)                                       := 'DELETE_LAST';

c_FS_DIR_BIZ_UNIT       CONSTANT INFAR006_OUTBOUND.GROUP_BU%TYPE                    := '7350';

c_STATUS_NEW            CONSTANT ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE     := 'NEW';
c_STATUS_SELECTED       CONSTANT ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE     := 'SELECTED';
c_STATUS_BATCHED        CONSTANT ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE     := 'BATCHED';
c_STATUS_TRANSMIT       CONSTANT ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE     := 'TRANSMITTED';
c_STATUS_FAILED         CONSTANT ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE     := 'FAILED';
c_STATUS_NOT_XMIT       CONSTANT ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE     := 'NOT_TRANSMITTED';

c_DR                    CONSTANT VARCHAR2(2)                                        := 'DR';
c_CR                    CONSTANT VARCHAR2(2)                                        := 'CR';
c_WO                    CONSTANT VARCHAR2(2)                                        := 'WO';
c_DRYEC                 CONSTANT VARCHAR2(5)                                        := 'DRYEC';
c_CRYEC                 CONSTANT VARCHAR2(5)                                        := 'CRYEC';

c_A_LINE                CONSTANT VARCHAR2(1)                                        := 'A';
c_U_LINE                CONSTANT VARCHAR2(1)                                        := 'U';
c_REVERSE               CONSTANT VARCHAR2(1)                                        := 'R';
c_NOT_REVERSE           CONSTANT VARCHAR2(1)                                        := 'N';
c_GROUP_TYPE            CONSTANT VARCHAR2(1)                                        := 'B';
c_POST_ACTION           CONSTANT VARCHAR2(1)                                        := 'L';

c_BATCH_COMPLETE        CONSTANT BATCH.STATUS%TYPE                                  := 'C';
c_BATCH_TRANSMIT        CONSTANT BATCH.STATUS%TYPE                                  := 'T';
c_BATCH_NOT_XMIT        CONSTANT BATCH.STATUS%TYPE                                  := 'N';
c_BATCH_ERROR           CONSTANT BATCH.STATUS%TYPE                                  := 'E';

c_FISCAL_OUTBOUND_ERR   CONSTANT BATCH.STATUS%TYPE                                  := 'FISCAL_OUTBOUND';

c_A_DST_SEQ_NUM         CONSTANT INFAR006_OUTBOUND.DST_SEQ_NUM%TYPE                 := 100;
c_U_DST_SEQ_NUM         CONSTANT INFAR006_OUTBOUND.DST_SEQ_NUM%TYPE                 := 1;
       
c_TC_101                CONSTANT VARCHAR2(15)                                       := '101';
c_TC_142                CONSTANT VARCHAR2(15)                                       := '142';
c_TC_456                CONSTANT VARCHAR2(15)                                       := '456';

c_EVENT_010             CONSTANT EVENT_TYPE.EVENT_TYPE_CODE%TYPE                    := '010';
c_EVENT_015             CONSTANT EVENT_TYPE.EVENT_TYPE_CODE%TYPE                    := '015';
c_EVENT_900             CONSTANT EVENT_TYPE.EVENT_TYPE_CODE%TYPE                    := '900';
c_EVENT_325             CONSTANT EVENT_TYPE.EVENT_TYPE_CODE%TYPE                    := '325';
c_EVENT_330             CONSTANT EVENT_TYPE.EVENT_TYPE_CODE%TYPE                    := '330';
c_EVENT_331             CONSTANT EVENT_TYPE.EVENT_TYPE_CODE%TYPE                    := '331';

c_PU_EV                 CONSTANT PROGRAM_UNIT.PROGRAM_UNIT_CODE%TYPE                := 'EV';
c_PU_PV                 CONSTANT PROGRAM_UNIT.PROGRAM_UNIT_CODE%TYPE                := 'PV';
c_PU_ART                CONSTANT PROGRAM_UNIT.PROGRAM_UNIT_CODE%TYPE                := 'ART';
c_PU_CALOSHA            CONSTANT PROGRAM_UNIT.PROGRAM_UNIT_CODE%TYPE                := 'CALOSHA';

c_COLL_DOSH             CONSTANT PROGRAM_UNIT.PROGRAM_UNIT_CODE%TYPE                := 'ACCTDOSH';

c_DEPOSIT_PREFIX        CONSTANT REFERENCE_CODE_LIST.DOMAIN_NAME%TYPE               := 'DEPOSIT_ID_PREFIX';
c_GROUP_PREFIX          CONSTANT REFERENCE_CODE_LIST.DOMAIN_NAME%TYPE               := 'GROUP_ID_PREFIX';
c_DISTRIBUTION_LINE     CONSTANT REFERENCE_CODE_LIST.DOMAIN_NAME%TYPE               := 'DISTRIBUTION_LINE';
c_DIR_DUE_DATE          CONSTANT REFERENCE_CODE_LIST.DOMAIN_NAME%TYPE               := 'DIR_DUE_DATE';


c_INFAR006_CARS_A       CONSTANT REFERENCE_CODE_LIST.DOMAIN_NAME%TYPE               := 'INFAR006_CARS_A';
c_INFAR006_CARS_S       CONSTANT REFERENCE_CODE_LIST.DOMAIN_NAME%TYPE               := 'INFAR006_CARS_S';
C_INFAR001_CARS         CONSTANT REFERENCE_CODE_LIST.DOMAIN_NAME%TYPE               := 'INFAR001_CARS';
C_INFAR018_CARS         CONSTANT REFERENCE_CODE_LIST.DOMAIN_NAME%TYPE               := 'INFAR018_CARS';

c_FH_ROW_ID             CONSTANT INFAR001_OUTBOUND.FS_ROW_ID%TYPE                   := '000';    
c_DC_ROW_ID             CONSTANT INFAR001_OUTBOUND.FS_ROW_ID%TYPE                   := '001';
c_PI_ROW_ID             CONSTANT INFAR001_OUTBOUND.FS_ROW_ID%TYPE                   := '002';
c_IR_ROW_ID             CONSTANT INFAR001_OUTBOUND.FS_ROW_ID%TYPE                   := '003';
c_CI_ROW_ID             CONSTANT INFAR001_OUTBOUND.FS_ROW_ID%TYPE                   := '004';
c_DJ_ROW_ID             CONSTANT INFAR001_OUTBOUND.FS_ROW_ID%TYPE                   := '005';

c_LOW_SEVERITY          CONSTANT CARS_ERROR_LOG.SEVERITY%TYPE                       := 'LOW';
c_MEDIUM_SEVERITY       CONSTANT CARS_ERROR_LOG.SEVERITY%TYPE                       := 'MEDIUM';
c_HIGH_SEVERITY         CONSTANT CARS_ERROR_LOG.SEVERITY%TYPE                       := 'HIGH';

c_SYSDATE               CONSTANT INFAR006_OUTBOUND.CREATED_DATE%TYPE                :=  SYSDATE ;
c_USER                  CONSTANT INFAR006_OUTBOUND.CREATED_BY%TYPE                  :=  USER ;
c_CARS_DB               CONSTANT INFAR006_OUTBOUND.DATA_SOURCE_CODE%TYPE            := 'CARS';

c_UNC_COLL_ACCTG        CONSTANT REVENUE_SOURCE_CODE.REVENUE_SOURCE_CODE%TYPE       := '';
c_UNC_COLL_ACCTG        CONSTANT REVENUE_SOURCE_CODE.REVENUE_SOURCE_CODE%TYPE       := '';

-- Array to mamange the INFAR006 counter and Amounts
TYPE INFAR006_COUNT_REC IS RECORD (
    RECORD_ID               INFAR006_OUTBOUND.BATCH_ID%TYPE,
    BATCH_ID                INFAR006_OUTBOUND.BATCH_ID%TYPE,
    PROGRAM_UNIT_CODE       PROGRAM_UNIT.PROGRAM_UNIT_CODE %TYPE,
    DATA_SOURCE_CODE        INFAR006_OUTBOUND.DATA_SOURCE_CODE%TYPE,
    GROUP_SEQ_NUM           INFAR006_OUTBOUND.GROUP_SEQ_NUM%TYPE,  
    GROUP_ID_STG            INFAR006_OUTBOUND.GROUP_ID_STG%TYPE,
    CONTROL_AMT             INFAR006_OUTBOUND.CONTROL_AMT%TYPE,
    CONTROL_CNT             INFAR006_OUTBOUND.CONTROL_CNT%TYPE
);

-- Array Variablea to mamange the data.
V_INFAR006_COUNT_REC        INFAR006_COUNT_REC;
V_INFAR006_EMPTY_REC        INFAR006_COUNT_REC;

TYPE INFAR006_TBL IS TABLE OF INFAR006_COUNT_REC;   -- Collection, Table of Records or Array
v_INFAR006_TBL INFAR006_TBL := INFAR006_TBL();      -- Instantiate the Collection

-- Array to mamange the INFAR01 counter and Amounts
TYPE INFAR001_COUNTER_REC IS RECORD (
    RECORD_ID               INFAR001_OUTBOUND.BATCH_ID%TYPE,
    BATCH_ID                INFAR001_OUTBOUND.BATCH_ID%TYPE,
    PROGRAM_UNIT_CODE       PROGRAM_UNIT.PROGRAM_UNIT_CODE %TYPE,
    DATA_SOURCE_CODE        INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE,
    DEPOSIT_ID              INFAR001_OUTBOUND.DEPOSIT_ID%TYPE,
    DEPOSIT_CNT             INFAR001_OUTBOUND.DEPOSIT_CNT%TYPE,         -- TOTAL DEPOSITS IN THE DATA FILE 
    TOTAL_AMT               INFAR001_OUTBOUND.TOTAL_AMT%TYPE,           -- SUM OF ALL DEPOSITS IN THE DATA FILE 
    PAYMENT_SEQ_NUM         INFAR001_OUTBOUND.PAYMENT_SEQ_NUM%TYPE ,  
    ID_SEQ_NUM              INFAR001_OUTBOUND.ID_SEQ_NUM%TYPE,
    DST_SEQ_NUM             INFAR001_OUTBOUND.DST_SEQ_NUM%TYPE,
    CONTROL_AMT             INFAR001_OUTBOUND.CONTROL_AMT%TYPE,         -- SUM OF AMOUNT IN THE DEPOSIT 
    CONTROL_CNT             INFAR001_OUTBOUND.CONTROL_CNT%TYPE          -- TOTAL LINE ITEMS IN THE DEPOSIT
);
       
-- Array Variablea to mamange the data.
V_INFAR001_COUNT_REC        INFAR001_COUNTER_REC;
V_INFAR001_EMPTY_REC        INFAR001_COUNTER_REC;

TYPE INFAR001_TBL IS TABLE OF INFAR001_COUNTER_REC;   -- Collection, Table of Records or Array
v_INFAR001_TBL INFAR001_TBL := INFAR001_TBL();      -- Instantiate the Collection

    -- INFAR001 FUNCTIONS
    FUNCTION FUNC_GET_FS_DEPOSIT(
                programUnit    VARCHAR2, 
                eventDate      DATE, 
                depositSlip    VARCHAR2, 
                depositDate    DATE, 
                receiptType    VARCHAR2)  RETURN VARCHAR2;
                
    FUNCTION FUNC_GET_BILLED_PP_SW(programUnitCode IN VARCHAR2) RETURN VARCHAR2;
    
    FUNCTION FUNC_GET_FS_PAYMENT_METHOD(receiptType VARCHAR2) RETURN VARCHAR2;
    
    FUNCTION FUNC_GET_FS_DEPOSIT_PFX(programUnitCode VARCHAR2) RETURN VARCHAR2;
    
    FUNCTION FUNC_GET_FS_DEPOSIT_TYPE(receiptType   VARCHAR2) RETURN VARCHAR2;
        
    -- INFAR006 FUNCTIONS AND PROCEDURES
    FUNCTION GET_FS_ADDRESS_ID(varReferenceDoc      VARCHAR2)   RETURN VARCHAR2;
    
    FUNCTION GET_FS_CUSTOMER_ID(varReferenceDoc     VARCHAR2)   RETURN VARCHAR2;
    
    FUNCTION GET_FS_AS_OF_DATE(varReferenceDoc      VARCHAR2)   RETURN DATE;
    
    FUNCTION GET_FS_DIR_PAYMENT_TERMS(varRefValue   VARCHAR2)   RETURN VARCHAR2;
    
    FUNCTION GET_FS_CREDIT_AMOUNT(varAcctEntryId    NUMBER)     RETURN VARCHAR2;
    
    FUNCTION GET_FS_DEBIT_AMOUNT(varAcctEntryId     NUMBER)     RETURN VARCHAR2;
    
    FUNCTION GET_FS_GL_REV_SRC( 
                varAcctEntryId      NUMBER, 
                varSystemDefined    VARCHAR2, 
                varFsEntryType      VARCHAR2, 
                varTransactionCode  VARCHAR2)   RETURN VARCHAR2;
                                
    FUNCTION GET_FS_ALT_ACCT(
                varRevenueSrcCode   VARCHAR2, 
                varAgencySrcCode    VARCHAR2, 
                varTransactionCode  VARCHAR2)   RETURN VARCHAR2;
                              
    FUNCTION GET_FS_SYSTEM_DEFINED(varRefValue  VARCHAR2)   RETURN VARCHAR2;
    
    FUNCTION GET_FS_LINE_NUMBER(
                varRootDocument     VARCHAR2, 
                varProgramUnit      VARCHAR2)   RETURN VARCHAR2;
                                
    FUNCTION GET_FS_ITEM_LINE(  
                varRootDocument     VARCHAR2, 
                varTransactionCode  VARCHAR, 
                varProgramUnit      VARCHAR2)   RETURN VARCHAR2;
                                
    FUNCTION GET_FS_ENT_TYPE_REVERSE(p_entry_type   VARCHAR2)   RETURN VARCHAR2;
    
    FUNCTION GET_FS_ENT_RSN_REVERSE(p_entry_reason  VARCHAR2)   RETURN VARCHAR2 ;
    
    FUNCTION IS_REVERSAL_EVENT(varEventTypeCode VARCHAR2) RETURN NUMBER;

    FUNCTION FUNC_GET_FISCAL_YEAR(varRootDoc IN VARCHAR2) RETURN VARCHAR2;

    FUNCTION FUNC_GET_FISCAL_MONTH(varDate IN DATE) RETURN VARCHAR2;

    FUNCTION FUNC_GET_PRIOR_FISCAL_YEAR(varRootDoc IN VARCHAR2) RETURN VARCHAR2;
    
    PROCEDURE UPDATE_ACCTG_ENTRY_STATUS(
                varStatus           ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE, 
                varBatchDate        DATE, 
                varProgramUnit      PROGRAM_UNIT.PROGRAM_UNIT_CODE%TYPE,    
                varTransactionCode  ACCOUNTING_ENTRY_TYPE.ACCTG_TRANSACT_CODE%TYPE,
                varEventType        VARCHAR2, 
                varLastBatchDate    DATE,
                varCurrentStatus    ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE
                );  
        
    -- BATCH PROCESS FUNCTIONS AND PROCEDURES
    PROCEDURE LOG_BATCH_ERROR(
                p_errorDetail   CARS_ERROR_LOG.ERROR_DETAIL%TYPE,
                p_errorCode     CARS_ERROR_LOG.ERROR_CODE%TYPE,
                p_errorMessage  CARS_ERROR_LOG.ERROR_MESSAGE%TYPE
                );

    FUNCTION FS_BATCH_TRIAL_RUN RETURN NUMBER; 

    PROCEDURE FS_BATCH_HEADER(  
                varBatchId          BATCH.BATCH_ID%TYPE, 
                varBatchNumber      BATCH.BATCH_NUMBER%TYPE,
                varBatchDate        BATCH.BATCH_DATE%TYPE, 
                varBatchType        BATCH.BATCH_TYPE_CODE%TYPE,
                P_SUCCESS_FLAG     OUT VARCHAR2,
                P_MESSAGE          OUT VARCHAR2
                );

    PROCEDURE UPDATE_STATUS_BY_ID(
                varStatus       ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE,
                varBatchDate    DATE, 
                varAcctgEntryId NUMBER
                );
        
    PROCEDURE FS_BATCH_DRIVER(
                P_SUCCESS_FLAG      OUT VARCHAR2,
                P_MESSAGE           OUT VARCHAR2);        
  
    PROCEDURE UPD_EVENT_900_STATUS(batchDate      DATE,
                P_SUCCESS_FLAG    OUT VARCHAR2,
                P_MESSAGE         OUT VARCHAR2);        
  
    PROCEDURE UPD_EVENT_WO_STATUS(batchDate      DATE,
                P_SUCCESS_FLAG    OUT VARCHAR2,
                P_MESSAGE         OUT VARCHAR2);
     
    PROCEDURE GET_INFAR006_COUNTER_DATA(
                P_BATCH_ID            INFAR006_OUTBOUND.BATCH_ID%TYPE,
                P_PROGRAM_UNIT_CODE   PROGRAM_UNIT.PROGRAM_UNIT_CODE %TYPE, 
                P_DATA_SOURCE_CODE    INFAR006_OUTBOUND.DATA_SOURCE_CODE%TYPE,
                P_CONTROL_AMT         INFAR006_OUTBOUND.CONTROL_AMT%TYPE,
                P_ACTION              INFAR006_OUTBOUND.DATA_SOURCE_CODE%TYPE,
                P_SUCCESS_FLAG    OUT VARCHAR2,
                P_MESSAGE         OUT VARCHAR2
                );

    PROCEDURE GET_INFAR001_COUNTER_DATA(
                P_BATCH_ID            INFAR001_OUTBOUND.BATCH_ID%TYPE,
                P_PROGRAM_UNIT_CODE   PROGRAM_UNIT.PROGRAM_UNIT_CODE %TYPE, 
                P_DATA_SOURCE_CODE    INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE,
                P_CONTROL_AMT         INFAR001_OUTBOUND.CONTROL_AMT%TYPE,
                P_ACTION              INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE,
                P_SUCCESS_FLAG    OUT VARCHAR2,
                P_MESSAGE         OUT VARCHAR2
                );

    PROCEDURE UPD_INFAR006_COUNTER_DATA(
                P_BATCH_ID            INFAR006_OUTBOUND.BATCH_ID%TYPE,
                P_PROGRAM_UNIT_CODE   PROGRAM_UNIT.PROGRAM_UNIT_CODE %TYPE, 
                P_DATA_SOURCE_CODE    INFAR006_OUTBOUND.DATA_SOURCE_CODE%TYPE,
                P_ACTION              INFAR006_OUTBOUND.DATA_SOURCE_CODE%TYPE,
                P_SUCCESS_FLAG    OUT VARCHAR2,
                P_MESSAGE         OUT VARCHAR2
                );

    PROCEDURE UPD_INFAR001_COUNTER_DATA(
                P_BATCH_ID            INFAR001_OUTBOUND.BATCH_ID%TYPE,
                P_PROGRAM_UNIT_CODE   PROGRAM_UNIT.PROGRAM_UNIT_CODE %TYPE, 
                P_DATA_SOURCE_CODE    INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE,
                P_ACTION              INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE,
                P_SUCCESS_FLAG    OUT VARCHAR2,
                P_MESSAGE         OUT VARCHAR2
                );

    PROCEDURE UPD_INFAR001_HEADER_DATA(
                P_BATCH_ID            INFAR001_OUTBOUND.BATCH_ID%TYPE,
                P_PROGRAM_UNIT_CODE   PROGRAM_UNIT.PROGRAM_UNIT_CODE %TYPE, 
                P_DATA_SOURCE_CODE    INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE,
                P_ACTION              INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE,
                P_SUCCESS_FLAG    OUT VARCHAR2,
                P_MESSAGE         OUT VARCHAR2
                );
                
    PROCEDURE UPD_INFAR006_ZERO_BAL(
                batchDate  DATE,
                P_SUCCESS_FLAG    OUT VARCHAR2,
                P_MESSAGE         OUT VARCHAR2);
    
    PROCEDURE GET_INFAR006_DATA (
                P_BATCH_ID              INFAR006_OUTBOUND.BATCH_ID%TYPE,
                P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
                P_PROGRAM_UNIT          PROGRAM_UNIT.PROGRAM_UNIT_CODE%TYPE,    
                P_TRANSACTION_CODE      ACCOUNTING_ENTRY_TYPE.ACCTG_TRANSACT_CODE%TYPE,
                P_EVENT_TYPE_CODE       VARCHAR2,
                P_LAST_BATCH_DATE       DATE,
                P_SUCCESS_FLAG      OUT VARCHAR2,
                P_MESSAGE           OUT VARCHAR2    
            ) ;

    PROCEDURE INSERT_INFAR006_DATA (
            P_BATCH_ID              INFAR006_OUTBOUND.BATCH_ID%TYPE,
            P_PROGRAM_UNIT          VARCHAR2,
            P_ACCOUNTING_DT         INFAR006_OUTBOUND.ACCOUNTING_DT%TYPE,
            P_CUST_ID               INFAR006_OUTBOUND.CUST_ID%TYPE,
            P_ITEM                  INFAR006_OUTBOUND.ITEM%TYPE,
            P_ITEM_LINE             INFAR006_OUTBOUND.ITEM_LINE%TYPE,
            P_ENTRY_TYPE            INFAR006_OUTBOUND.ENTRY_TYPE%TYPE,    
            P_ENTRY_REASON          INFAR006_OUTBOUND.ENTRY_REASON%TYPE,
            P_ENTRY_AMT             INFAR006_OUTBOUND.ENTRY_AMT%TYPE, 
            P_ASOF_DT               INFAR006_OUTBOUND.ASOF_DT%TYPE,
            P_PYMNT_TERMS_CD        INFAR006_OUTBOUND.PYMNT_TERMS_CD%TYPE,
            P_ADDRESS_SEQ_NUM       INFAR006_OUTBOUND.ADDRESS_SEQ_NUM%TYPE,             
            P_DST_SEQ_NUM           INFAR006_OUTBOUND.DST_SEQ_NUM%TYPE,
            P_SYSTEM_DEFINED        INFAR006_OUTBOUND.SYSTEM_DEFINED%TYPE, 
            P_MONETARY_AMOUNT       INFAR006_OUTBOUND.MONETARY_AMOUNT%TYPE,
            P_ACCOUNT               INFAR006_OUTBOUND.ACCOUNT%TYPE,
            P_ALTACCT               INFAR006_OUTBOUND.ALTACCT%TYPE,
            P_DEPTID                INFAR006_OUTBOUND.DEPTID%TYPE,
            P_PRODUCT               INFAR006_OUTBOUND.PRODUCT%TYPE,
            P_FUND_CODE             INFAR006_OUTBOUND.FUND_CODE%TYPE,
            P_CONTROL_AMT           INFAR006_OUTBOUND.CONTROL_AMT%TYPE,
            P_CONTROL_CNT           INFAR006_OUTBOUND.CONTROL_CNT%TYPE,
            P_GROUP_ID_STG          INFAR006_OUTBOUND.GROUP_ID_STG%TYPE,
            P_GROUP_SEQ_NUM         INFAR006_OUTBOUND.GROUP_SEQ_NUM%TYPE,            
            P_ACCTG_ENTRY_ID        NUMBER,  
            P_CHARTFIELD1           INFAR006_OUTBOUND.CHARTFIELD1%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            );        
            
    --  Inserts Header Line for INFAR001
    --  Row ID = 000
    --
    PROCEDURE INSERT_INFAR001_DATA (
            P_BATCH_ID              INFAR001_OUTBOUND.BATCH_ID%TYPE,
            P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
            P_CREATED_DTTM          INFAR001_OUTBOUND.CREATED_DTTM%TYPE,
            P_DEPOSIT_BU            INFAR001_OUTBOUND.DEPOSIT_BU%TYPE,
            P_DEPOSIT_CNT           INFAR001_OUTBOUND.DEPOSIT_CNT%TYPE,
            P_TOTAL_AMT             INFAR001_OUTBOUND.TOTAL_AMT%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            );
    --  Inserts Deposit Control for INFAR001
    --  Row ID = 001
    --
    PROCEDURE INSERT_INFAR001_DATA (
            P_BATCH_ID              INFAR001_OUTBOUND.BATCH_ID%TYPE,
            P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
            P_PROGRAM_UNIT          INFAR001_OUTBOUND.PROGRAM_UNIT_CODE%TYPE, 
            P_DEPOSIT_BU            INFAR001_OUTBOUND.DEPOSIT_BU%TYPE,
            P_DEPOSIT_ID            INFAR001_OUTBOUND.DEPOSIT_ID%TYPE,
            P_ACCOUNTING_DT         INFAR001_OUTBOUND.ACCOUNTING_DT%TYPE,
            P_BANK_CD               INFAR001_OUTBOUND.BANK_CD%TYPE,
            P_BANK_ACCT_KEY         INFAR001_OUTBOUND.BANK_ACCT_KEY%TYPE,
            P_DEPOSIT_TYPE          INFAR001_OUTBOUND.DEPOSIT_TYPE%TYPE,
            P_CONTROL_CURRENCY      INFAR001_OUTBOUND.CONTROL_CURRENCY%TYPE,
            P_ZZ_BNK_DEPOSIT_NUM    INFAR001_OUTBOUND.ZZ_BNK_DEPOSIT_NUM%TYPE,
            P_ZZ_IDENTIFIER         INFAR001_OUTBOUND.ZZ_IDENTIFIER%TYPE,
            P_CONTROL_AMT           INFAR001_OUTBOUND.CONTROL_AMT%TYPE,
            P_CONTROL_CNT           INFAR001_OUTBOUND.CONTROL_CNT%TYPE,
            P_RECEIVED_DT           INFAR001_OUTBOUND.RECEIVED_DT%TYPE,
            P_TOTAL_CHECKS          INFAR001_OUTBOUND.TOTAL_CHECKS%TYPE,
            P_FLAG                  INFAR001_OUTBOUND.FLAG%TYPE,
            P_BANK_OPER_NUM         INFAR001_OUTBOUND.BANK_OPER_NUM%TYPE,
            P_ZZ_LEG_DEP_ID         INFAR001_OUTBOUND.ZZ_LEG_DEP_ID%TYPE,
            P_ACCTG_ENTRY_ID        INFAR001_OUTBOUND.ACCTG_ENTRY_ID%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            );
    --  Inserts Payment Information for INFAR001
    -- Row ID = 002
    --
    PROCEDURE INSERT_INFAR001_DATA (
            P_BATCH_ID              INFAR001_OUTBOUND.BATCH_ID%TYPE,
            P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
            P_PROGRAM_UNIT          INFAR001_OUTBOUND.PROGRAM_UNIT_CODE%TYPE, 
            P_DEPOSIT_BU            INFAR001_OUTBOUND.DEPOSIT_BU%TYPE,
            P_DEPOSIT_ID            INFAR001_OUTBOUND.DEPOSIT_ID%TYPE,
            P_PAYMENT_SEQ_NUM       INFAR001_OUTBOUND.PAYMENT_SEQ_NUM%TYPE,
            P_PAYMENT_ID            INFAR001_OUTBOUND.PAYMENT_ID%TYPE,
            P_ACCOUNTING_DT         INFAR001_OUTBOUND.ACCOUNTING_DT%TYPE,
            P_PAYMENT_AMT           INFAR001_OUTBOUND.PAYMENT_AMT%TYPE,
            P_PAYMENT_CURRENCY      INFAR001_OUTBOUND.PAYMENT_CURRENCY%TYPE,
            P_PP_SW                 INFAR001_OUTBOUND.PP_SW%TYPE,
            P_MISC_PAYMENT          INFAR001_OUTBOUND.MISC_PAYMENT%TYPE,
            P_CHECK_DT              INFAR001_OUTBOUND.CHECK_DT%TYPE,
            P_ZZ_PAYMENT_METHOD     INFAR001_OUTBOUND.ZZ_PAYMENT_METHOD%TYPE,
            P_ZZ_RECEIVED_BY_SCO    INFAR001_OUTBOUND.ZZ_RECEIVED_BY_SCO%TYPE,
            P_ZZ_CASH_TYPE          INFAR001_OUTBOUND.ZZ_CASH_TYPE%TYPE,
            P_DESCR50_MIXED         INFAR001_OUTBOUND.DESCR50_MIXED%TYPE,
            P_DOCUMENT              INFAR001_OUTBOUND.DOCUMENT%TYPE,
            P_CITY                  INFAR001_OUTBOUND.CITY%TYPE,
            P_COUNTY                INFAR001_OUTBOUND.COUNTY%TYPE,
            P_TAX_AMT               INFAR001_OUTBOUND.TAX_AMT%TYPE,
            P_LINE_NOTE_TEXT        INFAR001_OUTBOUND.LINE_NOTE_TEXT%TYPE,
            P_ACCTG_ENTRY_ID        INFAR001_OUTBOUND.ACCTG_ENTRY_ID%TYPE,
            P_ROOT_DOCUMENT         EVENT.AR_ROOT_DOCUMENT%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            );
    
    --  Inserts Item Reference for INFAR001
    --  Row ID = 003
    --
    PROCEDURE INSERT_INFAR001_DATA (
            P_BATCH_ID              INFAR001_OUTBOUND.BATCH_ID%TYPE,
            P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
            P_PROGRAM_UNIT          INFAR001_OUTBOUND.PROGRAM_UNIT_CODE%TYPE, 
            P_DEPOSIT_BU            INFAR001_OUTBOUND.DEPOSIT_BU%TYPE,
            P_DEPOSIT_ID            INFAR001_OUTBOUND.DEPOSIT_ID%TYPE,
            P_PAYMENT_SEQ_NUM       INFAR001_OUTBOUND.PAYMENT_SEQ_NUM%TYPE,
            P_ID_SEQ_NUM            INFAR001_OUTBOUND.ID_SEQ_NUM%TYPE,
            P_REF_QUALIFIER_CODE    INFAR001_OUTBOUND.REF_QUALIFIER_CODE%TYPE,
            P_REF_VALUE             INFAR001_OUTBOUND.REF_VALUE%TYPE,
            P_ACCTG_ENTRY_ID        INFAR001_OUTBOUND.ACCTG_ENTRY_ID%TYPE,
            P_ROOT_DOCUMENT         EVENT.AR_ROOT_DOCUMENT%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            );
            
    --  Inserts Customer Information for INFAR001
    --  Row ID = 004
    --
    PROCEDURE INSERT_INFAR001_DATA (
            P_BATCH_ID              INFAR001_OUTBOUND.BATCH_ID%TYPE,
            P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
            P_PROGRAM_UNIT          INFAR001_OUTBOUND.PROGRAM_UNIT_CODE%TYPE, 
            P_DEPOSIT_BU            INFAR001_OUTBOUND.DEPOSIT_BU%TYPE,
            P_DEPOSIT_ID            INFAR001_OUTBOUND.DEPOSIT_ID%TYPE,
            P_PAYMENT_SEQ_NUM       INFAR001_OUTBOUND.PAYMENT_SEQ_NUM%TYPE,
            P_ID_SEQ_NUM            INFAR001_OUTBOUND.ID_SEQ_NUM%TYPE,
            P_CUST_ID               INFAR001_OUTBOUND.CUST_ID%TYPE,
            P_ACCTG_ENTRY_ID        INFAR001_OUTBOUND.ACCTG_ENTRY_ID%TYPE,
            P_ROOT_DOCUMENT         EVENT.AR_ROOT_DOCUMENT%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            );
            
    --  Inserts Direct Journal - Distribution for INFAR001
    --  Row ID = 005
    --
    PROCEDURE INSERT_INFAR001_DATA (
            P_BATCH_ID              INFAR001_OUTBOUND.BATCH_ID%TYPE,
            P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
            P_PROGRAM_UNIT          INFAR001_OUTBOUND.PROGRAM_UNIT_CODE%TYPE, 
            P_DEPOSIT_BU            INFAR001_OUTBOUND.DEPOSIT_BU%TYPE,
            P_DEPOSIT_ID            INFAR001_OUTBOUND.DEPOSIT_ID%TYPE,
            P_PAYMENT_SEQ_NUM       INFAR001_OUTBOUND.PAYMENT_SEQ_NUM%TYPE,
            P_DST_SEQ_NUM           INFAR001_OUTBOUND.DST_SEQ_NUM%TYPE,
            P_BUSINESS_UNIT_GL      INFAR001_OUTBOUND.BUSINESS_UNIT_GL%TYPE,
            P_SPEEDCHART_KEY        INFAR001_OUTBOUND.SPEEDCHART_KEY%TYPE,
            P_MONETARY_AMOUNT       INFAR001_OUTBOUND.MONETARY_AMOUNT%TYPE,
            P_ACCOUNT               INFAR001_OUTBOUND.ACCOUNT%TYPE,
            P_RESOURCE_TYPE         INFAR001_OUTBOUND.RESOURCE_TYPE%TYPE,
            P_RESOURCE_CATEGORY     INFAR001_OUTBOUND.RESOURCE_CATEGORY%TYPE,
            P_RESOURCE_SUB_CAT      INFAR001_OUTBOUND.RESOURCE_SUB_CAT%TYPE,
            P_ANALYSIS_TYPE         INFAR001_OUTBOUND.ANALYSIS_TYPE%TYPE,
            P_OPERATING_UNIT        INFAR001_OUTBOUND.OPERATING_UNIT%TYPE,
            P_PRODUCT               INFAR001_OUTBOUND.PRODUCT%TYPE,
            P_FUND_CODE             INFAR001_OUTBOUND.FUND_CODE%TYPE,
            P_CLASS_FLD             INFAR001_OUTBOUND.CLASS_FLD%TYPE,
            P_PROGRAM_CODE          INFAR001_OUTBOUND.PROGRAM_CODE%TYPE,
            P_BUDGET_REF            INFAR001_OUTBOUND.BUDGET_REF%TYPE,
            P_AFFILIATE             INFAR001_OUTBOUND.AFFILIATE%TYPE,
            P_AFFILIATE_INTRA1      INFAR001_OUTBOUND.AFFILIATE_INTRA1%TYPE,
            P_AFFILIATE_INTRA2      INFAR001_OUTBOUND.AFFILIATE_INTRA2%TYPE,
            P_CHARTFIELD1           INFAR001_OUTBOUND.CHARTFIELD1%TYPE,
            P_CHARTFIELD2           INFAR001_OUTBOUND.CHARTFIELD2%TYPE,
            P_CHARTFIELD3           INFAR001_OUTBOUND.CHARTFIELD3%TYPE,
            P_ALTACCT               INFAR001_OUTBOUND.ALTACCT%TYPE,
            P_DEPTID                INFAR001_OUTBOUND.DEPTID%TYPE,
            P_FUND                  INFAR001_OUTBOUND.FUND%TYPE,
            P_SUBFUND               INFAR001_OUTBOUND.SUBFUND%TYPE,
            P_PROGRAM               INFAR001_OUTBOUND.PROGRAM%TYPE,
            P_ELEMENT               INFAR001_OUTBOUND.ELEMENT%TYPE,
            P_COMPONENT             INFAR001_OUTBOUND.COMPONENT%TYPE,
            P_TASK                  INFAR001_OUTBOUND.TASK%TYPE,
            P_PCA                   INFAR001_OUTBOUND.PCA%TYPE,
            P_ORG_CODE              INFAR001_OUTBOUND.ORG_CODE%TYPE,
            P_INDEX_CODE            INFAR001_OUTBOUND.INDEX_CODE%TYPE,
            P_OBJECT_DETAIL         INFAR001_OUTBOUND.OBJECT_DETAIL%TYPE,
            P_AGENCY_OBJECT         INFAR001_OUTBOUND.AGENCY_OBJECT%TYPE,
            P_SOURCE                INFAR001_OUTBOUND.SOURCE%TYPE,
            P_AGENCY_SOURCE         INFAR001_OUTBOUND.AGENCY_SOURCE%TYPE,
            P_GL_ACCOUNT            INFAR001_OUTBOUND.GL_ACCOUNT%TYPE,
            P_SUBSIDIARY            INFAR001_OUTBOUND.SUBSIDIARY%TYPE,
            P_FUND_SOURCE           INFAR001_OUTBOUND.FUND_SOURCE%TYPE,
            P_CHARACTER             INFAR001_OUTBOUND.CHARACTER%TYPE,
            P_METHOD                INFAR001_OUTBOUND.METHOD%TYPE,
            P_YEAR                  INFAR001_OUTBOUND.YEAR%TYPE,
            P_REFERENCE             INFAR001_OUTBOUND.REFERENCE%TYPE,
            P_FFY                   INFAR001_OUTBOUND.FFY%TYPE,
            P_APPROPRIATION_SYMBOL  INFAR001_OUTBOUND.APPROPRIATION_SYMBOL%TYPE,
            P_PROJECT               INFAR001_OUTBOUND.PROJECT%TYPE,
            P_WORK_PHASE            INFAR001_OUTBOUND.WORK_PHASE%TYPE,
            P_MULTIPURPOSE          INFAR001_OUTBOUND.MULTIPURPOSE%TYPE,
            P_LOCATION              INFAR001_OUTBOUND.LOCATION%TYPE,
            P_DEPT_USE_1            INFAR001_OUTBOUND.DEPT_USE_1%TYPE,
            P_DEPT_USE_2            INFAR001_OUTBOUND.DEPT_USE_2%TYPE,
            P_BUDGET_DT             INFAR001_OUTBOUND.BUDGET_DT%TYPE,
            P_LINE_DESCR            INFAR001_OUTBOUND.LINE_DESCR%TYPE,
            P_OPEN_ITEM_KEY         INFAR001_OUTBOUND.OPEN_ITEM_KEY%TYPE,
            P_ACCTG_ENTRY_ID        INFAR001_OUTBOUND.ACCTG_ENTRY_ID%TYPE,
            P_ROOT_DOCUMENT         EVENT.AR_ROOT_DOCUMENT%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            );
           
    PROCEDURE GET_INFAR001_DATA (
        P_BATCH_ID              INFAR006_OUTBOUND.BATCH_ID%TYPE,
        P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
        P_PROGRAM_UNIT          PROGRAM_UNIT.PROGRAM_UNIT_CODE%TYPE,
        P_TRANSACT_CODE         ACCOUNTING_ENTRY_TYPE.ACCTG_TRANSACT_CODE%TYPE,
        P_TRANSACT_REVS         ACCOUNTING_ENTRY_TYPE.TRANSACTION_REVERSAL%TYPE
        );

    PROCEDURE LOG_CARS_ERROR(
                p_errorLevel    CARS_ERROR_LOG.ERROR_LEVEL%TYPE,
                p_severity      CARS_ERROR_LOG.SEVERITY%TYPE,
                p_errorDetail   CARS_ERROR_LOG.ERROR_DETAIL%TYPE,
                p_errorCode     CARS_ERROR_LOG.ERROR_CODE%TYPE,
                p_errorMessage  CARS_ERROR_LOG.ERROR_MESSAGE%TYPE,
                p_dataSource    CARS_ERROR_LOG.DATA_SOURCE_CODE%TYPE
                );
                
END FS_INTERFACE_PKG;
/
