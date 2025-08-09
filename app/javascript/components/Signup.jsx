import React, { useState } from "react";

function Signup() {
	
	const [formData, setFormData] = useState({

		username:'',
		password:'',
		
	});
	
	const handleChange = (e) => {
		
		const {name, value} = e.target;
		setFormData({...formData, [name]: value});
		
	}
	
	
	return (
	
	<div className='signup-form-container'>	

	<form className= 'signup-form' method='post' action='/signup'>
			
    		<div className='signup-header-container'>
		
			<h2 className='signup-heading'> Sign Up </h2>
    		</div>
			
			<input type = 'text' name='username' placeholder='Username' className='email-pass' value={formData.username} onChange={handleChange}/>
			<input type = 'password' name= 'password' placeholder='Password' className='email-pass' value={formData.password}
			onChange={handleChange}/>
		
	   	 	<input type="hidden" name="authenticity_token" 
			value={document.querySelector("meta[name='csrf-token']")?.getAttribute("content")}/>
		
			<input type = 'submit' value='Submit' className='signup-submit'/>
			
			<p className='signup-pac'>Already have an account? <a href='/login'> Log In </a> </p> 
			
		</form>
		</div>
	)	
}

export default Signup;