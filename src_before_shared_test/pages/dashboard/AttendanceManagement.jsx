import {Navigate} from 'react-router-dom';
// Registrar attendance uses the existing live report, not a second placeholder.
export default function AttendanceManagement(){
 return <Navigate to="/admin/reports?report=attendance" replace/>;
}
