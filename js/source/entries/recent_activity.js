
import '../legacy/jquery.js';

export function init(start_date, end_date, include_dateless_items) {

    update_tables(start_date, end_date, include_dateless_items);
}

    
export function update_tables(start_date, end_date, include_dateless_items) { 
    
    jQuery('#recent_activity_trials').DataTable( {
	ajax : '/',
	
    }
    );
    
    jQuery('#recent_activity_phenotypes').DataTable({}
	
    );
    
    
    jQuery('#recent_activity_accessions').DataTable({}
	
    );
    
    jQuery('#recent_activity_plots').DataTable({}
	
    );
    
    
}