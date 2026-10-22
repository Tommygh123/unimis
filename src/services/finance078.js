import {supabase} from "../lib/supabase";
const wrap=async p=>{try{const {data,error}=await p;return {data,error}}catch(error){return {data:null,error}}};
export const loadFinanceWorkspace=(from,to)=>wrap(supabase.rpc("unimis_finance_workspace",{p_from:from||null,p_to:to||null}));
export const loadFinanceReports=(from,to)=>wrap(supabase.rpc("unimis_finance_reports",{p_from:from||null,p_to:to||null}));
export const seedChartOfAccounts=()=>wrap(supabase.rpc("unimis_seed_chart_of_accounts"));
export const postFinanceJournal=j=>wrap(supabase.rpc("unimis_post_finance_journal",{p_journal:j}));
export const recordExpense=expense=>wrap(supabase.rpc("unimis_post_expense_accounting",{p_expense:expense}));
export const loadStudentFinanceStatement=()=>wrap(supabase.rpc("unimis_student_finance_statement"));
export const loadFinanceSetup=()=>wrap(supabase.rpc("unimis_finance_setup"));
export const seedFeeTypes=()=>wrap(supabase.rpc("unimis_seed_fee_types"));
export const saveFeeStructure=x=>wrap(supabase.rpc("unimis_save_fee_structure",{p_structure:x}));
export const loadFeeStructure=id=>wrap(supabase.rpc("unimis_fee_structure_detail",{p_id:id}));
export const generateFeeInvoice=id=>wrap(supabase.rpc("unimis_generate_fee_invoice",{p_student_id:id}));
export const bulkGenerateFeeInvoices=ids=>wrap(supabase.rpc("unimis_bulk_generate_fee_invoices",{p_student_ids:ids}));
export const recordStudentPayment=x=>wrap(supabase.rpc("unimis_record_student_payment",{p_payment:x}));
export const loadFinanceDocument=(type,id)=>wrap(supabase.rpc("unimis_finance_document",{p_type:type,p_id:id}));

export const generatePeriodFeeInvoices=f=>wrap(supabase.rpc("unimis_generate_period_fee_invoices",{p_faculty_id:f.faculty_id||null,p_department_id:f.department_id||null,p_programme_id:f.programme_id||null,p_level:f.level_number?Number(f.level_number):null,p_student_type:f.student_type||null}));

export const createFeeType=x=>wrap(supabase.rpc("unimis_create_fee_type",{p_name:x.name,p_code:x.code||null,p_description:x.description||null,p_is_mandatory:x.is_mandatory!==false}));

export const previewPeriodFeeInvoices=f=>wrap(supabase.rpc("unimis_preview_period_fee_invoices",{p_faculty_id:f.faculty_id||null,p_department_id:f.department_id||null,p_programme_id:f.programme_id||null,p_level:f.level_number?Number(f.level_number):null,p_student_type:f.student_type||null}));
export const loadStudentFinanceLedger=id=>wrap(supabase.rpc("unimis_student_finance_ledger",{p_student_id:id}));

export const loadFinanceAnalyticsFilters=()=>wrap(supabase.rpc("unimis_finance_analytics_filter_options"));
export const loadFinanceAnalytics=f=>wrap(supabase.rpc("unimis_finance_analytics_workspace",{p_filters:f}));
export const loadFinanceOperationChecks=(from,to)=>wrap(supabase.rpc('unimis_finance_operation_checks',{p_from:from,p_to:to}));
export const applyInvoiceWaiver=x=>wrap(supabase.rpc('unimis_apply_invoice_waiver',{p_invoice_id:x.invoice_id,p_amount:Number(x.amount),p_reference:x.reference,p_reason:x.reason}));

export const voidStudentPayment=(id,reason)=>wrap(supabase.rpc('unimis_void_student_payment124',{p_payment_id:id,p_reason:reason}));
export const correctStudentPayment=(id,reason,payment)=>wrap(supabase.rpc('unimis_correct_student_payment124',{p_payment_id:id,p_reason:reason,p_payment:payment}));
export const loadApplicationRevenue=filters=>wrap(supabase.rpc('unimis_application_revenue124',{p_filters:filters}));
