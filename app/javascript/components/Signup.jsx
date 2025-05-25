import React, { useState } from "react";

function Signup() {
	
	const nextState = () => {
		
		setCurrentState(2)
	
	}
	
	const prevState = () => {
		
		setCurrentState(1)
	
	}
		
	const [currentState, setCurrentState] = useState(1);
	
	const [formData, setFormData] = useState({

		email:'',
		password:'',
		firstName:'',
		middleName:'',
		lastName:'',
		gender:'',
		dateOfBirth:''	
		
	});
	
	const handleChange = (e) => {
		
		const {name, value} = e.target;
		setFormData({...formData, [name]: value});
		
	}
	
	
	
	return (
	
	<div className='signup-form-container'>	

	<form className= 'signup-form' method='post' action='/signup'>
	
	
		{currentState === 1 && (
			<>
			
    		<div className='signup-header-container'>
			<div>
			</div>			
			<h2 className='signup-heading'> Sign Up </h2>
    		</div>
			<input type = 'email' name='email' placeholder='Email' className='email-pass' value={formData.email} onChange={handleChange}/>
			<input type = 'password' name= 'password' placeholder='Password' className='email-pass' value={formData.password}
			onChange={handleChange}/>
			<button type='button' className='signup-submit' onClick={nextState}>Next</button>
			<p className='signup-pac'>Already have an account? <a href='/login'> Log In </a> </p> 
			</>	
		)}
		
		{currentState === 2 && (
			<>
  		  <div className='signup-header-container'>
            <button onClick={prevState} className='signup-back-button'> &lt; back</button>
			<h2 className='signup-heading'> Sign Up </h2>
  		  </div>
			<input type ='text' name='firstName' placeholder='First Name' className='email-pass' value={formData.firstName} 
			onChange={handleChange}/>
			<input type='text' name='middleName' placeholder='Middle Name (optional)' className='email-pass' value={formData.middleName}
			onChange={handleChange}/>
			<input type='text' name='lastName' placeholder='Last Name' className='email-pass' value={formData.lastName}
			onChange={handleChange}/>
			<select name='gender' class ='email-pass' onChange={handleChange} value={formData.gender} required>
		    	<option value="">Choose gender</option>
				<option value='male'>Male</option>
				<option value='female'>Female</option>
				<option value='non-binary'>Non-Binary</option>
				<option value='fluid'>Fluid</option>
				<option value='prefer_not_to_say'>Prefer Not To Say</option>
			</select>
			<div class='date-wrapper'>
			<input type='date' class='date-email-pass' name='dateOfBirth' onChange={handleChange} value={formData.dateOfBirth}/>
			<p class='dob-text'>&nbsp;&nbsp;&nbsp;Date of Birth</p>
			</div>
	   	 	<input type="hidden" name="authenticity_token" 
			value={document.querySelector("meta[name='csrf-token']")?.getAttribute("content")}/>
			<input type='hidden' name='email' value={formData.email}/>
			<input type='hidden' name='password' value={formData.password}/>
			<input type = 'submit' value='Submit' className='signup-submit'/>
			</>	
			
			)}
			
		</form>
		</div>
	)	
}

export default Signup;