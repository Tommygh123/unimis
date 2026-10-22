export const entities152={
  "staff": {
    "title": "Employee Directory",
    "domain": "hr",
    "table": "staff",
    "fields": [
      {
        "name": "staff_number",
        "label": "Staff Number",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "first_name",
        "label": "First Name",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "last_name",
        "label": "Last Name",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "email",
        "label": "Email",
        "type": "email",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "phone",
        "label": "Phone",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "user_id",
        "label": "Linked login",
        "type": "select",
        "required": false,
        "source": "users",
        "options": null
      },
      {
        "name": "department_id",
        "label": "Department Id",
        "type": "select",
        "required": false,
        "source": "departments",
        "options": null
      },
      {
        "name": "job_title",
        "label": "Job Title",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "hire_date",
        "label": "Hire Date",
        "type": "date",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "staff_category",
        "label": "Staff Category",
        "type": "select",
        "required": false,
        "source": null,
        "options": [
          "academic",
          "non_academic",
          "management",
          "support",
          "contract",
          "other"
        ]
      }
    ],
    "columns": [
      "staff_number",
      "first_name",
      "last_name",
      "email",
      "phone",
      "user_id"
    ],
    "status": "employment_status",
    "flow": {
      "active": [
        "suspended",
        "leave",
        "retired",
        "resigned",
        "terminated",
        "inactive"
      ],
      "probation": [
        "active",
        "suspended"
      ],
      "suspended": [
        "active"
      ],
      "leave": [
        "active"
      ],
      "inactive": [
        "active"
      ]
    }
  },
  "jobs": {
    "title": "Recruitment Vacancies",
    "domain": "hr",
    "table": "unimis_jobs152",
    "fields": [
      {
        "name": "title",
        "label": "Title",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "department_id",
        "label": "Department Id",
        "type": "select",
        "required": false,
        "source": "departments",
        "options": null
      },
      {
        "name": "positions",
        "label": "Positions",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "closing_date",
        "label": "Closing Date",
        "type": "date",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "description",
        "label": "Description",
        "type": "textarea",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "requirements",
        "label": "Requirements",
        "type": "textarea",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "title",
      "department_id",
      "positions",
      "closing_date",
      "description",
      "requirements"
    ],
    "status": "status",
    "flow": {
      "draft": [
        "open",
        "cancelled"
      ],
      "open": [
        "closed",
        "cancelled"
      ]
    }
  },
  "candidates": {
    "title": "Recruitment Candidates",
    "domain": "hr",
    "table": "unimis_candidates152",
    "fields": [
      {
        "name": "job_id",
        "label": "Job Id",
        "type": "select",
        "required": true,
        "source": "jobs",
        "options": null
      },
      {
        "name": "first_name",
        "label": "First Name",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "last_name",
        "label": "Last Name",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "email",
        "label": "Email",
        "type": "email",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "phone",
        "label": "Phone",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "evidence",
        "label": "Qualifications / interview evidence",
        "type": "textarea",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "job_id",
      "first_name",
      "last_name",
      "email",
      "phone",
      "evidence"
    ],
    "status": "status",
    "flow": {
      "applied": [
        "shortlisted",
        "rejected"
      ],
      "shortlisted": [
        "interviewed",
        "rejected"
      ],
      "interviewed": [
        "offered",
        "rejected"
      ],
      "offered": [
        "hired",
        "rejected"
      ]
    }
  },
  "leave_types": {
    "title": "Leave Policies",
    "domain": "hr",
    "table": "leave_types",
    "fields": [
      {
        "name": "name",
        "label": "Name",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "code",
        "label": "Code",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "description",
        "label": "Description",
        "type": "textarea",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "default_days",
        "label": "Default Days",
        "type": "number",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "is_paid",
        "label": "Is Paid",
        "type": "checkbox",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "name",
      "code",
      "description",
      "default_days",
      "is_paid"
    ],
    "status": "status",
    "flow": {
      "active": [
        "inactive"
      ],
      "inactive": [
        "active"
      ]
    }
  },
  "balances": {
    "title": "Leave Entitlements",
    "domain": "hr",
    "table": "staff_leave_balances",
    "fields": [
      {
        "name": "staff_id",
        "label": "Staff Id",
        "type": "select",
        "required": true,
        "source": "staff",
        "options": null
      },
      {
        "name": "leave_type_id",
        "label": "Leave Type Id",
        "type": "select",
        "required": true,
        "source": "leave_types",
        "options": null
      },
      {
        "name": "academic_year_id",
        "label": "Academic Year Id",
        "type": "select",
        "required": true,
        "source": "years",
        "options": null
      },
      {
        "name": "opening_balance",
        "label": "Opening Balance",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "accrued_days",
        "label": "Accrued Days",
        "type": "number",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "adjusted_days",
        "label": "Adjusted Days",
        "type": "number",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "staff_id",
      "leave_type_id",
      "academic_year_id",
      "opening_balance",
      "used_days",
      "remaining_days"
    ],
    "status": null,
    "flow": {}
  },
  "leave": {
    "title": "Leave Requests",
    "domain": "hr",
    "table": "leave_requests",
    "fields": [
      {
        "name": "staff_id",
        "label": "Staff Id",
        "type": "select",
        "required": true,
        "source": "staff",
        "options": null
      },
      {
        "name": "leave_type_id",
        "label": "Leave Type Id",
        "type": "select",
        "required": true,
        "source": "leave_types",
        "options": null
      },
      {
        "name": "start_date",
        "label": "Start Date",
        "type": "date",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "end_date",
        "label": "End Date",
        "type": "date",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "reason",
        "label": "Reason",
        "type": "textarea",
        "required": true,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "staff_id",
      "leave_type_id",
      "start_date",
      "end_date",
      "requested_days",
      "status"
    ],
    "status": "status",
    "flow": {
      "submitted": [
        "approved",
        "rejected",
        "cancelled"
      ],
      "approved": [
        "cancelled",
        "completed"
      ]
    }
  },
  "sites": {
    "title": "Attendance Sites",
    "domain": "hr",
    "table": "unimis_sites152",
    "fields": [
      {
        "name": "name",
        "label": "Name",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "latitude",
        "label": "Latitude",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "longitude",
        "label": "Longitude",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "radius_m",
        "label": "Geofence radius (metres)",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "require_gps",
        "label": "Require Gps",
        "type": "checkbox",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "nfc_token",
        "label": "NFC campus tag code",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "start_time",
        "label": "Start Time",
        "type": "time",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "grace_minutes",
        "label": "Grace Minutes",
        "type": "number",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "timezone",
        "label": "Timezone",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "name",
      "radius_m",
      "require_gps",
      "start_time",
      "timezone"
    ],
    "status": null,
    "flow": {}
  },
  "attendance": {
    "title": "Staff Attendance",
    "domain": "hr",
    "table": "unimis_staff_attendance152",
    "fields": [],
    "columns": [
      "staff_id",
      "work_date",
      "check_in",
      "check_out",
      "method",
      "late_minutes",
      "status"
    ],
    "status": "status",
    "flow": {}
  },
  "exceptions": {
    "title": "Attendance Exceptions",
    "domain": "hr",
    "table": "unimis_attendance_exceptions152",
    "fields": [
      {
        "name": "staff_id",
        "label": "Staff Id",
        "type": "select",
        "required": true,
        "source": "staff",
        "options": null
      },
      {
        "name": "work_date",
        "label": "Work Date",
        "type": "date",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "requested_in",
        "label": "Requested In",
        "type": "datetime-local",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "requested_out",
        "label": "Requested Out",
        "type": "datetime-local",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "reason",
        "label": "Reason",
        "type": "textarea",
        "required": true,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "staff_id",
      "work_date",
      "requested_in",
      "requested_out",
      "reason"
    ],
    "status": "status",
    "flow": {
      "submitted": [
        "approved",
        "rejected"
      ]
    }
  },
  "performance": {
    "title": "Performance Reviews",
    "domain": "hr",
    "table": "unimis_performance152",
    "fields": [
      {
        "name": "staff_id",
        "label": "Staff Id",
        "type": "select",
        "required": true,
        "source": "staff",
        "options": null
      },
      {
        "name": "period_start",
        "label": "Period Start",
        "type": "date",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "period_end",
        "label": "Period End",
        "type": "date",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "model",
        "label": "Model",
        "type": "select",
        "required": true,
        "source": null,
        "options": [
          "kpi",
          "competency",
          "balanced"
        ]
      },
      {
        "name": "kpi_score",
        "label": "Kpi Score",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "competency_score",
        "label": "Competency Score",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "kpi_weight",
        "label": "KPI weighting %",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "evidence",
        "label": "Evidence",
        "type": "textarea",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "goals",
        "label": "Goals",
        "type": "textarea",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "development_plan",
        "label": "Development Plan",
        "type": "textarea",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "staff_id",
      "period_start",
      "period_end",
      "model",
      "final_score",
      "status"
    ],
    "status": "status",
    "flow": {
      "draft": [
        "submitted"
      ],
      "submitted": [
        "approved",
        "returned"
      ],
      "returned": [
        "submitted"
      ],
      "approved": [
        "acknowledged"
      ]
    }
  },
  "suppliers": {
    "title": "Suppliers",
    "domain": "procurement",
    "table": "suppliers",
    "fields": [
      {
        "name": "name",
        "label": "Name",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "contact_person",
        "label": "Contact Person",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "email",
        "label": "Email",
        "type": "email",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "phone",
        "label": "Phone",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "address",
        "label": "Address",
        "type": "textarea",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "name",
      "contact_person",
      "email",
      "phone",
      "address"
    ],
    "status": "status",
    "flow": {
      "active": [
        "inactive"
      ],
      "inactive": [
        "active"
      ]
    }
  },
  "requisitions": {
    "title": "Purchase Requisitions",
    "domain": "procurement",
    "table": "purchase_requisitions",
    "fields": [
      {
        "name": "department_id",
        "label": "Department Id",
        "type": "select",
        "required": false,
        "source": "departments",
        "options": null
      },
      {
        "name": "purpose",
        "label": "Purpose",
        "type": "textarea",
        "required": true,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "requisition_no",
      "department_id",
      "request_date",
      "purpose",
      "estimated_total",
      "status"
    ],
    "status": "status",
    "flow": {
      "draft": [
        "submitted",
        "cancelled"
      ],
      "submitted": [
        "approved",
        "rejected"
      ],
      "approved": [
        "cancelled"
      ]
    }
  },
  "req_items": {
    "title": "Requisition Items",
    "domain": "procurement",
    "table": "unimis_requisition_items152",
    "fields": [
      {
        "name": "requisition_id",
        "label": "Requisition Id",
        "type": "select",
        "required": true,
        "source": "requisitions",
        "options": null
      },
      {
        "name": "description",
        "label": "Description",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "quantity",
        "label": "Quantity",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "unit_cost",
        "label": "Unit Cost",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "requisition_id",
      "description",
      "quantity",
      "unit_cost",
      "line_total"
    ],
    "status": null,
    "flow": {}
  },
  "orders": {
    "title": "Purchase Orders",
    "domain": "procurement",
    "table": "purchase_orders",
    "fields": [
      {
        "name": "supplier_id",
        "label": "Supplier Id",
        "type": "select",
        "required": true,
        "source": "suppliers",
        "options": null
      },
      {
        "name": "requisition_id",
        "label": "Requisition Id",
        "type": "select",
        "required": true,
        "source": "requisitions",
        "options": null
      },
      {
        "name": "currency_code",
        "label": "Currency Code",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "po_number",
      "supplier_id",
      "requisition_id",
      "order_date",
      "total_amount",
      "status"
    ],
    "status": "status",
    "flow": {
      "draft": [
        "approved",
        "cancelled"
      ],
      "approved": [
        "sent",
        "cancelled"
      ]
    }
  },
  "receipts": {
    "title": "Goods Received",
    "domain": "procurement",
    "table": "unimis_goods_receipts152",
    "fields": [
      {
        "name": "order_id",
        "label": "Order Id",
        "type": "select",
        "required": true,
        "source": "orders",
        "options": null
      },
      {
        "name": "order_item_id",
        "label": "Order Item Id",
        "type": "select",
        "required": true,
        "source": "order_items",
        "options": null
      },
      {
        "name": "quantity",
        "label": "Quantity",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "delivery_reference",
        "label": "Delivery Reference",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "inspection_notes",
        "label": "Inspection Notes",
        "type": "textarea",
        "required": true,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "order_id",
      "order_item_id",
      "quantity",
      "delivery_reference",
      "status"
    ],
    "status": "status",
    "flow": {
      "draft": [
        "accepted",
        "rejected"
      ]
    }
  },
  "supplier_invoices": {
    "title": "Supplier Invoice Matching",
    "domain": "procurement",
    "table": "unimis_supplier_invoices152",
    "fields": [
      {
        "name": "order_id",
        "label": "Order Id",
        "type": "select",
        "required": true,
        "source": "orders",
        "options": null
      },
      {
        "name": "invoice_number",
        "label": "Invoice Number",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "invoice_date",
        "label": "Invoice Date",
        "type": "date",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "amount",
        "label": "Amount",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "order_id",
      "invoice_number",
      "invoice_date",
      "amount"
    ],
    "status": "status",
    "flow": {
      "submitted": [
        "matched",
        "rejected"
      ]
    }
  },
  "facilities": {
    "title": "Hostels & Facilities",
    "domain": "hostel",
    "table": "accommodation_facilities",
    "fields": [
      {
        "name": "name",
        "label": "Name",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "code",
        "label": "Code",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "gender_policy",
        "label": "Gender Policy",
        "type": "select",
        "required": true,
        "source": null,
        "options": [
          "male",
          "female",
          "mixed",
          "other"
        ]
      },
      {
        "name": "location",
        "label": "Location",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "description",
        "label": "Description",
        "type": "textarea",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "name",
      "code",
      "gender_policy",
      "location",
      "description"
    ],
    "status": "status",
    "flow": {
      "active": [
        "maintenance",
        "closed",
        "inactive"
      ],
      "maintenance": [
        "active"
      ],
      "closed": [
        "active"
      ],
      "inactive": [
        "active"
      ]
    }
  },
  "rooms": {
    "title": "Rooms",
    "domain": "hostel",
    "table": "accommodation_rooms",
    "fields": [
      {
        "name": "facility_id",
        "label": "Facility Id",
        "type": "select",
        "required": true,
        "source": "facilities",
        "options": null
      },
      {
        "name": "room_number",
        "label": "Room Number",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "floor_number",
        "label": "Floor Number",
        "type": "number",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "room_type",
        "label": "Room Type",
        "type": "select",
        "required": true,
        "source": null,
        "options": [
          "single",
          "double",
          "shared",
          "dormitory",
          "suite",
          "other"
        ]
      },
      {
        "name": "capacity",
        "label": "Capacity",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "facility_id",
      "room_number",
      "floor_number",
      "room_type",
      "capacity"
    ],
    "status": "status",
    "flow": {
      "available": [
        "maintenance",
        "closed"
      ],
      "full": [
        "maintenance"
      ],
      "maintenance": [
        "available"
      ],
      "closed": [
        "available"
      ]
    }
  },
  "beds": {
    "title": "Beds",
    "domain": "hostel",
    "table": "accommodation_beds",
    "fields": [
      {
        "name": "room_id",
        "label": "Room Id",
        "type": "select",
        "required": true,
        "source": "rooms",
        "options": null
      },
      {
        "name": "bed_code",
        "label": "Bed Code",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "room_id",
      "bed_code"
    ],
    "status": "status",
    "flow": {
      "available": [
        "maintenance",
        "inactive"
      ],
      "maintenance": [
        "available"
      ],
      "inactive": [
        "available"
      ]
    }
  },
  "hostel_applications": {
    "title": "Accommodation Applications",
    "domain": "hostel",
    "table": "accommodation_applications",
    "fields": [
      {
        "name": "student_id",
        "label": "Student Id",
        "type": "select",
        "required": true,
        "source": "students",
        "options": null
      },
      {
        "name": "academic_year_id",
        "label": "Academic Year Id",
        "type": "select",
        "required": true,
        "source": "years",
        "options": null
      },
      {
        "name": "academic_period_id",
        "label": "Academic Period Id",
        "type": "select",
        "required": false,
        "source": "periods",
        "options": null
      },
      {
        "name": "preferred_facility_id",
        "label": "Preferred Facility Id",
        "type": "select",
        "required": false,
        "source": "facilities",
        "options": null
      },
      {
        "name": "special_requirements",
        "label": "Special Requirements",
        "type": "textarea",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "student_id",
      "academic_year_id",
      "academic_period_id",
      "preferred_facility_id",
      "special_requirements"
    ],
    "status": "status",
    "flow": {
      "submitted": [
        "approved",
        "rejected",
        "waitlisted",
        "cancelled"
      ],
      "waitlisted": [
        "approved",
        "rejected",
        "cancelled"
      ]
    }
  },
  "allocations": {
    "title": "Allocation & Check-in",
    "domain": "hostel",
    "table": "accommodation_allocations",
    "fields": [
      {
        "name": "application_id",
        "label": "Application Id",
        "type": "select",
        "required": true,
        "source": "hostel_applications",
        "options": null
      },
      {
        "name": "bed_id",
        "label": "Bed Id",
        "type": "select",
        "required": true,
        "source": "beds",
        "options": null
      }
    ],
    "columns": [
      "student_id",
      "academic_year_id",
      "academic_period_id",
      "facility_id",
      "room_id",
      "bed_id",
      "allocation_status",
      "invoice_id152"
    ],
    "status": "allocation_status",
    "flow": {
      "allocated": [
        "checked_in",
        "cancelled"
      ],
      "checked_in": [
        "checked_out"
      ]
    }
  },
  "charges": {
    "title": "Accommodation Tariffs",
    "domain": "hostel",
    "table": "accommodation_charges",
    "fields": [
      {
        "name": "facility_id",
        "label": "Facility Id",
        "type": "select",
        "required": true,
        "source": "facilities",
        "options": null
      },
      {
        "name": "academic_year_id",
        "label": "Academic Year Id",
        "type": "select",
        "required": true,
        "source": "years",
        "options": null
      },
      {
        "name": "academic_period_id",
        "label": "Academic Period Id",
        "type": "select",
        "required": false,
        "source": "periods",
        "options": null
      },
      {
        "name": "room_type",
        "label": "Room Type",
        "type": "select",
        "required": false,
        "source": null,
        "options": [
          "single",
          "double",
          "shared",
          "dormitory",
          "suite",
          "other"
        ]
      },
      {
        "name": "amount",
        "label": "Amount",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "currency_code",
        "label": "Currency Code",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "facility_id",
      "academic_year_id",
      "academic_period_id",
      "room_type",
      "amount",
      "currency_code"
    ],
    "status": "status",
    "flow": {
      "active": [
        "inactive"
      ],
      "inactive": [
        "active"
      ]
    }
  },
  "incidents": {
    "title": "Hostel Incidents",
    "domain": "hostel",
    "table": "accommodation_incidents",
    "fields": [
      {
        "name": "student_id",
        "label": "Student Id",
        "type": "select",
        "required": true,
        "source": "students",
        "options": null
      },
      {
        "name": "incident_type",
        "label": "Incident Type",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "description",
        "label": "Description",
        "type": "textarea",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "action_taken",
        "label": "Action Taken",
        "type": "textarea",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "student_id",
      "incident_type",
      "description",
      "action_taken"
    ],
    "status": null,
    "flow": {}
  },
  "library_items": {
    "title": "Library Catalogue",
    "domain": "library",
    "table": "library_items",
    "fields": [
      {
        "name": "title",
        "label": "Title",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "author",
        "label": "Author",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "isbn",
        "label": "Isbn",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "publisher",
        "label": "Publisher",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "publication_year",
        "label": "Publication Year",
        "type": "number",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "description",
        "label": "Description",
        "type": "textarea",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "title",
      "author",
      "isbn",
      "publisher",
      "publication_year",
      "description"
    ],
    "status": "status",
    "flow": {}
  },
  "copies": {
    "title": "Library Copies",
    "domain": "library",
    "table": "library_copies",
    "fields": [
      {
        "name": "library_item_id",
        "label": "Library Item Id",
        "type": "select",
        "required": true,
        "source": "library_items",
        "options": null
      },
      {
        "name": "accession_number",
        "label": "Accession Number",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "barcode",
        "label": "Barcode",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "shelf_location",
        "label": "Shelf Location",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "library_item_id",
      "accession_number",
      "barcode",
      "shelf_location"
    ],
    "status": "availability_status",
    "flow": {}
  },
  "members": {
    "title": "Library Members",
    "domain": "library",
    "table": "library_members",
    "fields": [
      {
        "name": "member_number",
        "label": "Member Number",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "student_id",
        "label": "Student Id",
        "type": "select",
        "required": false,
        "source": "students",
        "options": null
      },
      {
        "name": "staff_id",
        "label": "Staff Id",
        "type": "select",
        "required": false,
        "source": "staff",
        "options": null
      },
      {
        "name": "member_type",
        "label": "Member Type",
        "type": "select",
        "required": true,
        "source": null,
        "options": [
          "student",
          "staff",
          "lecturer",
          "external",
          "other"
        ]
      },
      {
        "name": "max_items",
        "label": "Max Items",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "loan_days",
        "label": "Loan Days",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "member_number",
      "student_id",
      "staff_id",
      "member_type",
      "max_items",
      "loan_days"
    ],
    "status": "status",
    "flow": {}
  },
  "loans": {
    "title": "Library Circulation",
    "domain": "library",
    "table": "library_loans",
    "fields": [
      {
        "name": "member_id",
        "label": "Member Id",
        "type": "select",
        "required": true,
        "source": "members",
        "options": null
      },
      {
        "name": "copy_id",
        "label": "Copy Id",
        "type": "select",
        "required": true,
        "source": "copies",
        "options": null
      }
    ],
    "columns": [
      "member_id",
      "copy_id",
      "borrowed_at",
      "due_at",
      "returned_at",
      "loan_status"
    ],
    "status": "loan_status",
    "flow": {
      "borrowed": [
        "returned"
      ],
      "overdue": [
        "returned"
      ]
    }
  },
  "pay_profiles": {
    "title": "Employee Pay Profiles",
    "domain": "payroll",
    "table": "staff_payroll_profiles",
    "fields": [
      {
        "name": "staff_id",
        "label": "Staff Id",
        "type": "select",
        "required": true,
        "source": "staff",
        "options": null
      },
      {
        "name": "basic_salary",
        "label": "Basic Salary",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "salary_grade",
        "label": "Salary Grade",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "bank_name",
        "label": "Bank Name",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "bank_account_name",
        "label": "Bank Account Name",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "bank_account_number",
        "label": "Bank Account Number",
        "type": "text",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "effective_from",
        "label": "Effective From",
        "type": "date",
        "required": true,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "staff_id",
      "salary_grade",
      "basic_salary",
      "effective_from",
      "payroll_status"
    ],
    "status": "payroll_status",
    "flow": {
      "active": [
        "suspended",
        "inactive"
      ],
      "suspended": [
        "active"
      ],
      "inactive": [
        "active"
      ]
    }
  },
  "pay_components": {
    "title": "Pay Components",
    "domain": "payroll",
    "table": "pay_components",
    "fields": [
      {
        "name": "name",
        "label": "Name",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "code",
        "label": "Code",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "component_type",
        "label": "Component Type",
        "type": "select",
        "required": true,
        "source": null,
        "options": [
          "earning",
          "deduction",
          "employer_contribution"
        ]
      },
      {
        "name": "calculation_type",
        "label": "Calculation Type",
        "type": "select",
        "required": true,
        "source": null,
        "options": [
          "fixed",
          "percentage",
          "manual"
        ]
      },
      {
        "name": "percentage_basis",
        "label": "Percentage basis",
        "type": "select",
        "required": false,
        "source": null,
        "options": [
          "basic_salary"
        ]
      },
      {
        "name": "is_taxable",
        "label": "Is Taxable",
        "type": "checkbox",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "is_pensionable",
        "label": "Is Pensionable",
        "type": "checkbox",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "name",
      "code",
      "component_type",
      "calculation_type",
      "percentage_basis",
      "is_taxable"
    ],
    "status": "status",
    "flow": {}
  },
  "employee_components": {
    "title": "Employee Earnings & Deductions",
    "domain": "payroll",
    "table": "staff_pay_components",
    "fields": [
      {
        "name": "staff_id",
        "label": "Staff Id",
        "type": "select",
        "required": true,
        "source": "staff",
        "options": null
      },
      {
        "name": "pay_component_id",
        "label": "Pay Component Id",
        "type": "select",
        "required": true,
        "source": "pay_components",
        "options": null
      },
      {
        "name": "amount",
        "label": "Amount",
        "type": "number",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "percentage",
        "label": "Percentage",
        "type": "number",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "effective_from",
        "label": "Effective From",
        "type": "date",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "effective_to",
        "label": "Effective To",
        "type": "date",
        "required": false,
        "source": null,
        "options": null
      },
      {
        "name": "notes",
        "label": "Notes",
        "type": "textarea",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "staff_id",
      "pay_component_id",
      "amount",
      "percentage",
      "effective_from",
      "effective_to"
    ],
    "status": null,
    "flow": {}
  },
  "pay_periods": {
    "title": "Payroll Periods",
    "domain": "payroll",
    "table": "payroll_periods",
    "fields": [
      {
        "name": "name",
        "label": "Name",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "period_start",
        "label": "Period Start",
        "type": "date",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "period_end",
        "label": "Period End",
        "type": "date",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "payment_date",
        "label": "Payment Date",
        "type": "date",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "name",
      "period_start",
      "period_end",
      "payment_date"
    ],
    "status": "status",
    "flow": {}
  },
  "pay_runs": {
    "title": "Payroll Runs",
    "domain": "payroll",
    "table": "payroll_runs",
    "fields": [
      {
        "name": "payroll_period_id",
        "label": "Payroll Period Id",
        "type": "select",
        "required": true,
        "source": "pay_periods",
        "options": null
      }
    ],
    "columns": [
      "run_number",
      "payroll_period_id",
      "total_gross",
      "total_deductions",
      "total_net",
      "status"
    ],
    "status": "status",
    "flow": {
      "draft": [
        "completed",
        "cancelled"
      ],
      "completed": [
        "approved",
        "cancelled"
      ],
      "approved": []
    }
  },
  "payslips": {
    "title": "Payslips & Payments",
    "domain": "payroll",
    "table": "payslips",
    "fields": [],
    "columns": [
      "staff_id",
      "payroll_run_id",
      "basic_salary",
      "gross_pay",
      "total_deductions",
      "net_pay",
      "status"
    ],
    "status": "status",
    "flow": {}
  },
  "pay_lines": {
    "title": "Payslip Line Items",
    "domain": "payroll",
    "table": "payslip_lines",
    "fields": [],
    "columns": [
      "payslip_id",
      "description",
      "line_type",
      "amount"
    ],
    "status": null,
    "flow": {}
  },
  "objectives": {
    "title": "Performance Goals & Progress",
    "domain": "hr",
    "table": "unimis_objectives152",
    "fields": [
      {
        "name": "staff_id",
        "label": "Staff Id",
        "type": "select",
        "required": true,
        "source": "staff",
        "options": null
      },
      {
        "name": "title",
        "label": "Title",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "category",
        "label": "Category",
        "type": "select",
        "required": true,
        "source": null,
        "options": [
          "kpi",
          "competency",
          "milestone"
        ]
      },
      {
        "name": "start_date",
        "label": "Start Date",
        "type": "date",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "due_date",
        "label": "Due Date",
        "type": "date",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "target",
        "label": "Target",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "actual",
        "label": "Actual",
        "type": "number",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "unit",
        "label": "Unit",
        "type": "text",
        "required": true,
        "source": null,
        "options": null
      },
      {
        "name": "evidence",
        "label": "Evidence",
        "type": "textarea",
        "required": false,
        "source": null,
        "options": null
      }
    ],
    "columns": [
      "staff_id",
      "title",
      "category",
      "due_date",
      "target",
      "actual",
      "progress",
      "status"
    ],
    "status": "status",
    "flow": {
      "open": [
        "completed"
      ],
      "completed": [
        "accepted",
        "returned"
      ],
      "returned": [
        "completed"
      ]
    }
  }
};
