import React, { useState } from 'react'

const WithdrawButton = () => {
	
	const [isSubmitting, setIsSubmitting] = useState(false)
	const [isOpen, setIsOpen] = useState(false);
	
	const openDialog = () => setIsOpen(true);
	const closeDialog = () => setIsOpen(false);
	
	const handleSubmit = () => {
		
		setTimeout(() => setIsSubmitting(true), 10)
		
	}
	
	return (
		
		<> 
			<button className='add-withdraw-button' onClick={openDialog}>
				Withdraw Funds
			</button>
				
		{isOpen && (
			
			<div>
				<div className='background-overlay'></div>
				<div className='modal-dialog'>
				<div className='modal-header'>
						<h2>Withdraw Funds</h2>
				</div>
					<form className = 'modal-form' method='post' action='/balance' onSubmit={handleSubmit}>
	   	 				<input type="hidden" name="authenticity_token" 
						value={document.querySelector("meta[name='csrf-token']")?.getAttribute("content")}/>
			
						<div className='modal-amount'>
							<input type='number' placeholder='Amount' name='amount' min='0.01' step='0.01' className='shares-input' 
							disabled={isSubmitting}/>
						</div>
			
						<div className='modal-submit'>
							<button type='submit' name='commit' value='withdraw' className='aw-submit' disabled={isSubmitting}>
                            {isSubmitting ? 'Processing...' : 'Submit'}
							</button>
						</div>
			
					</form>
			
					<button className='close-button' onClick={closeDialog} disabled={isSubmitting}>
						X
					</button>
			
				</div>
				</div>
		)}
			</>
	);
};

export default WithdrawButton;
